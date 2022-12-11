#!/bin/bash
# shellcheck disable=SC2154,2034

# where we find the experiment results
resultpath="$RPATH/${NODES[0]}/"

# verify testresults
verifyExperiment() {

    # handle yao -O protocol variant, for some reason the result is only at node[1]
    # move to resultpath location
    while IFS= read -r file; do
        mv "$file" "$resultpath"
    done < <(find "$RPATH/${NODES[1]}/" -name "testresultsBINARYyaoO*" -print)

    for cdomain in "${CDOMAINS[@]}"; do
        declare -n cdProtocols="${cdomain}PROTOCOL"
        for protocol in "${cdProtocols[@]}"; do
            protocol=${protocol::-8}
            
            i=0
            loopinfo=$(find "$resultpath" -name "*$i.loop*" -print -quit)
            # while we find a next loop info file do
            while [ -n "$loopinfo" ]; do

                # get pos filepath of the measurements for the current loop
                experimentresult=$(find "$resultpath" -name "testresults$cdomain${protocol}_run*$i" -print -quit)
                verificationresult=$(find "$resultpath" -name "measurementlog${cdomain}_run*$i" -print -quit)

                # check existance of files
                if [ ! -f "$experimentresult" ] || [ ! -f "$verificationresult" ]; then
                    styleOrange "  Skip $protocol - File not found error: $experimentresult"
                    continue 2
                fi

                # verify experiment result - call experiment specific verify script
                chmod +x experiments/"$EXPERIMENT"/verify.py
                match=$(experiments/"$EXPERIMENT"/verify.py "$experimentresult" "$verificationresult")
                if [ "$match" != 1 ]; then
                    styleOrange "  Skip $protocol - $match at $experimentresult";
                    continue 2;
                fi
                ((++i))
                loopinfo=$(find "$resultpath" -name "*$i.loop*" -print -quit)
            done

            # only pass if while-loop actually entered
            [ "$i" -gt 0 ] && okfail ok "  verified - test passed for $protocol"
        done
    done
}

############
# Export experiment data from the pos_upload-ed logs into two tables
############
exportExperimentResults() {

    # set up location
    datatableShort="$EXPORTPATH/data/Eslice_short_results.csv"

    mkdir -p "$datatableShort"
    rm -rf "$datatableShort"

    dyncolumns=""
    # get the dynamic column names from the first .loop info file
    loopinfo=$(find "$resultpath" -name "*loop*" -print -quit)
    
    # check if loop file exists
    if [ -z "$loopinfo" ]; then
        okfail fail "nothing to export - no loop file found"
        return
    fi

    for columnname in $(jq -r 'keys_unsorted[]' "$loopinfo"); do
        dyncolumns+="$columnname"
        case "$columnname" in
            freqs) dyncolumns+="(GHz)";;
            quotas|packetdrops) dyncolumns+="(%)";;
            latencies) dyncolumns+="(ms)";;
            bandwidths) dyncolumns+="(Mbs)";;
        esac
        dyncolumns+=";"
    done

    # generate header line of data dump with column information
    basicInfo1="comp.time(s);comp.peakRAM(MiB);bin.filesize(MiB);"
    basicInfo2="${dyncolumns}runtime_internal(s);runtime_external(s);peakRAM(MiB);jobCPU(%)"
    echo -e "${basicInfo1}${basicInfo2}" > "$datatableShort"

    i=0
    # get loopfile path for the current variables
    loopinfo=$(find "$resultpath" -name "*$i.loop*" -print -quit)
    echo "  exporting testresults"
    # while we find a next loop info file do
    while [ -n "$loopinfo" ]; do
        loopvalues=""
        # extract loop var values
        for value in $(jq -r 'values[]' "$loopinfo"); do
            loopvalues+="$value;"
        done
        
        # get pos filepath of the measurements for the current loop
        runtimeinfo=$(find "$resultpath" -name "testresults*$i" -print -quit)
        if [ ! -f "$runtimeinfo" ] || [ ! -f "$runtimeinfo" ]; then
            styleOrange "    Skip - File not found error: testresults*$i"
            continue
        fi

        ## Minimum result measurement information
        ######
        # extract measurement
        compiletime=$(grep "Elapsed wall clock" "$runtimeinfo" | head -n 1 | cut -d ' ' -f 1)
        compilemaxRAMused=$(grep "Maximum resident" "$runtimeinfo" | head -n 1 | cut -d ' ' -f 1)
        binfsize=$(grep "Binary file size" "$runtimeinfo" | tail -n 1 | cut -d ' ' -f 1)
        [ -n "$compilemaxRAMused" ] && compilemaxRAMused="$((compilemaxRAMused/1024))"
        runtimeint=$(grep "computation chrono" "$runtimeinfo" | awk '{print $7}')
        runtimeext=$(grep "Elapsed wall clock" "$runtimeinfo" | tail -n 1 | cut -d ' ' -f 1)
        maxRAMused=$(grep "Maximum resident" "$runtimeinfo" | tail -n 1 | cut -d ' ' -f 1)
        [ -n "$maxRAMused" ] && maxRAMused="$((maxRAMused/1024))"
        jobCPU=$(grep "CPU this job" "$runtimeinfo" | cut -d '%' -f 1)
        maxRAMused=${maxRAMused:-NA}
        compilemaxRAMused=${compilemaxRAMused:-NA}

        commRounds=$(grep "Data sent =" "$runtimeinfo" | awk '{print $7}')
        dataSent=$(grep "Data sent =" "$runtimeinfo" | awk '{print $4}')
        globaldataSent=$(grep "Global data sent =" "$runtimeinfo" | awk '{print $5}')
        basicComm="${commRounds:-NA};${dataSent:-NA};${globaldataSent:-NA}"

        # put all collected info into one row (Short)
        basicInfo="${compiletime:-NA};$compilemaxRAMused;${binfsize:-NA}"
        echo -e "$basicInfo;$loopvalues$runtimeint;$runtimeext;$maxRAMused;$jobCPU" >> "$datatableShort"

        # locate next loop file
        ((++i))
        loopinfo=$(find "$resultpath" -name "*$i.loop*" -print -quit)
    done

    # check if there was something exported
    rowcount=$(wc -l "$datatableShort" | awk '{print $1}')
    if [ "$rowcount" -lt 2 ];then
        okfail fail "nothing to export"
        rm "$datatableShort"
        return
    fi

    # create a tab separated table for pretty formating
    # convert .csv -> .tsv
    column -s ';' -t "$datatableShort" > "${datatableShort::-3}"tsv
    okfail ok "exported short and full results (${datatableShort::-3}tsv)"

    # push to measurement data git
    repourl=$(grep "repoupload" global-variables.yml | cut -d ':' -f 2-)
    # check if upload git does not exist yet
    if [ ! -d git-upload/.git ]; then
        # clone the upload git repo
        # default to trust server fingerprint authenticity (usually insecure)
        GIT_SSH_COMMAND='ssh -o StrictHostKeyChecking=accept-new' git clone "${repourl// /}" git-upload
    fi

    echo " pushing experiment measurement data to git repo$repourl"
    cd git-upload || error ${LINENO} "${FUNCNAME[0]} cd into gitrepo failed"
    {
        # a pull is not really required, but for small sizes it doesn't hurt
        git pull
        # copy from local folder to git repo folder
        [ ! -d "${EXPORTPATH::-12}" ] && mkdir resultsMP-Slice/"${EXPORTPATH::-12}"
        cp -r ../"$EXPORTPATH" "${EXPORTPATH::-12}"
        git add . 
        git commit -a -m "script upload"
        git push 
    } &> /dev/null || error ${LINENO} "${FUNCNAME[0]} git upload failed"
        okfail ok " upload success" 
}
