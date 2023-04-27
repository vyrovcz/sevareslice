# Original Author Philipp Eisermann 
# Original Source https://github.com/Philipp-Eisermann/sevareparser
# Adapted version
# testing with dir="sevaremeasurements/results/2022-08/09_07-59-42"

import argparse
import os
import subprocess
import time

import re
import textwrap
import glob

colors = ['blue', 'red', 'orange', 'green', 'cyan', 'black']
nodehardware = {}
nodehardware.update({node: "Intel D-1518(2.2GHz) 32GiB 1Gbits" for node in ["dogecoin", "bitcoin", "ether", "todd", "rod", "ned"]})
nodehardware.update({node: "AMD 7543(2.8GHz) 512GiB 25Gbits" for node in ["algofi", "gard", "goracle", "zone"]})
nodehardware.update({node: "Intel 6312U(2.4GHz) 512GiB 25Gbits" for node in ["idex", "meld", "yieldly", "tinyman"]})

legenddict = {
    "1": "Sharemind",
    "2": "Replicated",
    "3": "Astra",
    "4": "OEC DUP",
    "5": "OEC REP",
    "6": "TTP",
    "7": "7",
    "8": "8",
    "9": "9",
    "d1": "bool",
    "d8": "char",
    "d64": "uint64",
    "d128": "SSE",
    "d256": "AVX",
    "d512": "AVX512",
    "all": "all"
}

def get_Specs(path):
    with open(glob.glob(path.split("plotted")[0] + "E*-run-summary.dat")[0], "r") as f:
        for line in f:
            match = re.search(r"Nodes.*", line)
            if match:
                node = match.group(0).split(" ")[2]
                return node + " " + nodehardware[node]

# Is used to generate the axis labels of plots
def get_name(prefix_):
    prefix_names = ["Datatype [bits]", "Threads", "txBuffer", "rxBuffer"] # Adaptions
    prefix_names += ["Latency [ms]", "Bandwidths [Mbit/s]", "Packet Loss [%]", "Frequency [GHz]", "Quotas [%]",
                    "CPU Threads", "Input Size"]  # Axis names
    prefixes_ = ["Dtp_", "Thd_", "txB_", "rxB_"] # Adaptions
    prefixes_ += ["Lat_", "Bwd_", "Pdr_", "Frq_", "Quo_", "Cpu_", "Inp_"]

    if prefix_ in prefixes_:
        return prefix_names[prefixes_.index(prefix_)]
    return prefix_

def indentor(file, indentation_level, text):
    file.write(textwrap.indent(text, prefix=" " * 4 * indentation_level) + os.linesep)

def getConsString(constellation):
    return "pre" + constellation["pre"] + "split" + constellation["split"] + "pack" + constellation["pack"] + "opt" + constellation["opt"] + "ssl" + constellation["ssl"] + "fun" + constellation["fun"]

def fileExists(path, substring):
    for file in os.listdir(path):
        if file.find(substring) != -1:
            return True
    return False

def genTex(tex_name, exp_prefix, plots, name, constellation, datatypemode=0):
    """
    Creates a .tex file for a single 2D plot
    :param tex_name: name of the tex file
    :param exp_prefix: bandwidth, cpus, freqs, etc
    :param plots: list of protocol names to be included in the plot
    :param name: Protocol, Datatype
    // Path + prefix + included_protocol must point to the txt datafile of the protocol
    """
    with open(tex_name, "w") as file:
        # indentor("file to write to", indentation level, code) the 'r' makes the string raw
        indentor(file, 0, "%% Built with sevareparser on day %%")
        indentor(file, 0, "%%      " + time.strftime("%d %B %Y", time.gmtime()) + "      %%")
        sectionname = r"\subsection{" + get_name(exp_prefix).split("[")[0] + name + " (" + legenddict[name.split(" ")[-1]] + ") " + getConsString(constellation) + "}"
        indentor(file, 0, sectionname)
        indentor(file, 0, r"\begin{frame}")
        indentor(file, 0, r"\frametitle{MP-Slice Runtimes " + get_name(exp_prefix).split("[")[0] + name + " (" + legenddict[name.split(" ")[-1]] + ")}")
        indentor(file, 0, r"\begin{figure}")
        indentor(file, 1, r"\begin{tikzpicture}[scale = 0.9]")
        # axis definition
        indentor(file, 2, r"\begin{axis}[")
        indentor(file, 3, "xlabel={" + get_name(exp_prefix) + "},")
        indentor(file, 3, "ylabel={runtime [s]},")
        indentor(file, 3, "scaled y ticks = false,y tick label style={/pgf/number format/fixed,/pgf/number format/precision=8},")
        indentor(file, 3, "scaled x ticks = false,x tick label style={/pgf/number format/fixed,/pgf/number format/precision=8},")
        indentor(file, 3, "legend style={anchor=west, legend pos=outer north east},")
        indentor(file, 3, "%xmax=0.1,")
        indentor(file, 3, "%ymax=0.1,")
        indentor(file, 2, "]")

        for g in range(len(plots)):
            plotpath = "../parsed/2D/"  + plots[g] + "_" + exp_prefix + getConsString(constellation) + ".txt"
            #print("    " + plotpath)
            divisor = plots[g].split("/")[1][1:]
            # this is for the special case where x axis shows the datatype bits, need to divide each y value by the x value
            divisor = divisor if divisor != "all" else r"\thisrowno{0}"
            dtypeNorm =  r" [y expr=\thisrowno{1} / " + divisor + "] "
            indentor(file, 3, r"\addplot[mark=|, thick, color=" + colors[g] + "] table" + dtypeNorm + " {" + plotpath + "};")
        
        mode = 1 if datatypemode else 0
        #print([plot.split("/") for plot in plots])
        indentor(file, 3, r"\legend{" + ', '.join([legenddict[key.split("/")[mode]] for key in plots ]) + "}")
        indentor(file, 2, r"\end{axis}")
        indentor(file, 1, r"\end{tikzpicture}")
        # Plot information summary
        indentor(file, 1, r"\begin{itemize}")
        indentor(file, 1, r"\fontsize{6pt}{8pt}\selectfont")
        indentor(file, 1, r"\item Ref.Problem: Scalable Search")
        indentor(file, 1, r"\item Library: MP-Slice - " + name + " (" + legenddict[name.split(" ")[-1]] + ")")
        indentor(file, 1, r"\item Metric: " + get_name(exp_prefix).split("[")[0] + " - runtime")
        switchpositions = "Preprocessing: " + constellation["pre"] + ", Split Roles: " + constellation["split"]
        switchpositions += ", Pack Bool: " + constellation["pack"] + ", Optimize Sharing: " + constellation["opt"]
        switchpositions +=  ", SSL: " + constellation["ssl"] + ", Function: " + constellation["fun"]
        indentor(file, 1, r"\item Switches: " + switchpositions)
        indentor(file, 1, r"\item Specs: " + get_Specs(tex_name))
        indentor(file, 1, r"\end{itemize}")

        indentor(file, 0, r"\end{figure}")
        indentor(file, 0, r"\end{frame}")

# - - - - - - - - ARGUMENTS - - - - - - - - - - -

parser = argparse.ArgumentParser(
    description='This program plots the results parsed by sevare parser.')

parser.add_argument('sevaredir', type=str, help='Required, testresults dir to plot.')
parser.add_argument('-f', "--force", action="store_true", help='(Optional) Force overwrite')

args = parser.parse_args()

sevaredir = args.sevaredir

if sevaredir[-1] != '/':
    sevaredir += '/'

# - - - - - - - - - INIT  - - - - - - - - - - - - -
# Check if the parser was executed before
if "parsed" not in os.listdir(sevaredir):
    print("Could not find the parsed directory, make sure you executed SevareParser before calling the plotter.")
    exit()

# Create directory
if os.path.exists(sevaredir + "plotted"):
    if not args.force:
        print("Error, \"plotted\"-folder exits. Run plotter with -f to force overwriting")
        exit()

    subprocess.run(["rm", "-rf", sevaredir + "plotted"])

os.mkdir(sevaredir + "plotted/")

# - - - - - - - - CREATE 2D PLOTS - - - - - - - - - - -

datatypes = []
prefixes = []  # will contain the variables for 2D plotting
constellations = [] # every entry is xxxx where x is either 0 or 1

print("Commencing 2D Plotting...")

# find out the protocols
protocols = sorted(os.listdir(sevaredir + "parsed/2D/"))
plots = os.listdir(sevaredir + "parsed/2D/" + protocols[0])

# capture all plotfiles to plot
for plot in plots:
    datatypes.append(plot.split("_")[0]) if plot.split("_")[0] != "dall" else None
    prefixes.append(plot.split("_")[1])
    constellation = {}
    for switch, position in re.findall(r'([A-Za-z]+)([0123456789])', plot.split("_")[2][:-4]):
        constellation[switch] = position
    constellations.append(constellation)

# remove duplicates
prefixes = [i for n, i in enumerate(prefixes) if i not in prefixes[:n]]
constellations = [i for n, i in enumerate(constellations) if i not in constellations[:n]]
datatypes = [i for n, i in enumerate(datatypes) if i not in datatypes[:n]]
datatypes = sorted(datatypes, key=lambda x: int(x[1:]))

# get highest input value from summary
maxinput = -1
maxdtype = -1
minspeed = ""
with open(glob.glob(sevaredir + "E*-run-summary.dat")[0], "r") as f:
    for line in f:
        match = re.search(r"Inputs.*", line)
        if match:
            numbers = [int(x) for x in re.findall(r'\b\d+\b', match.group(0))]
            maxinput = max(numbers)
        match = re.search(r"Datatypes.*", line)
        if match:
            numbers = [int(x) for x in re.findall(r'\b\d+\b', match.group(0))]
            maxdtype = max(numbers)   

print()
print("Recognized protocols: ", protocols)
print("Recognized datatypes: ", datatypes)
print("Recognized prefixes: ", prefixes)
#print(constellations)
print("First switch constellation: ", getConsString(constellations[0]))
#print(plots)
print()

# generate .tex files into an "include" folder
os.mkdir(sevaredir + "plotted/include")

## inputsize - runtime (should be always true)
######

if "Inp" not in prefixes:
    print("No *_Inp_* found, should exist in any correctly parsed folder")
    exit()

os.mkdir(sevaredir + "plotted/include/02input")

# protocol view
for constellation in constellations:
    for protocol in protocols:
        plots = [protocol + "/" + datatype for datatype in datatypes]
        savepath = "plotted/include/02input/0s" + protocol + "_" + getConsString(constellation) + ".tex"
        genTex(sevaredir + savepath, "Inp_", plots, " Protocol -s " + protocol, constellation, 1)
        print(" generated " + savepath)

# datatype view
for constellation in constellations:
    for i,datatype in enumerate(datatypes,2):
        plots = [protocol + "/" + datatype for protocol in protocols]
        savepath = "plotted/include/02input/0" + str(i) + datatype + "_" + getConsString(constellation) + ".tex"
        genTex(sevaredir + savepath, "Inp_", plots, " Datatype -d " + datatype, constellation)
        print(" generated " + savepath)

os.mkdir(sevaredir + "plotted/include/01manipulations")

## fixed input views, using the highest input value
######
# other manipulations
testtypes = ""
for i,prefix in enumerate(["Thd_", "txB_", "rxB_", "Lat_", "Bwd_", "Pdr_", "Frq_", "Quo_", "Cpu_"],2):
    if not fileExists(sevaredir + "parsed/2D/" + protocols[0], prefix):
        continue

    # skip single value plot files
    skip = False
    with open(glob.glob(sevaredir + "parsed/2D/" + protocols[0] + "/*" + prefix + "*")[0], "r") as f:
        skip = True if len(f.readlines()) < 2 else False
    if skip:
        continue

    testtypes += prefix
    for constellation in constellations:
        plots = [protocol + "/d" + str(maxdtype) for protocol in protocols]
        savepath = "plotted/include/01manipulations/0" + str(i) + "d" + str(maxdtype) + "_" + prefix + getConsString(constellation) + ".tex"
        genTex(sevaredir + savepath, prefix, plots, "Fixed Input: " + str(maxinput) + " -d " + datatype, constellation)
        print(" generated " + savepath)

testtypes = testtypes or "Inp_"

# datatypes
for constellation in constellations:
    plots = [protocol + "/dall" for protocol in protocols]
    savepath = "plotted/include/01manipulations/09dall" + "_" + getConsString(constellation) + ".tex"
    genTex(sevaredir + savepath, "Dtp_", plots, "Fixed Input: " + str(maxinput) + " all", constellation)
    print(" generated " + savepath)

### build main tex file
node = ""
aborted = ""
manipulation = ""
with open(sevaredir + "plotted/sevareplots.tex", "w") as file:
    indentor(file, 0, "%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%")
    indentor(file, 0, "%% Built with sevareparser on day")
    indentor(file, 0, "%%      " + time.strftime("%d %B %Y", time.gmtime()))
    indentor(file, 0, "%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%")
    indentor(file, 0, "")
    indentor(file, 0, r"\documentclass[8pt]{beamer}")
    indentor(file, 0, r"\setbeamertemplate{itemize item}{$-$}")
    indentor(file, 0, r"\usepackage{pgf}")
    indentor(file, 0, r"\usepackage{pgfplots}")
    indentor(file, 0, r"\pgfplotsset{compat=newest}")
    indentor(file, 0, r"\setbeamertemplate{itemize/enumerate body begin}{\small}")
    indentor(file, 0, r"\title{Sevarebench Measurement Results}")
    indentor(file, 0, r"\subtitle{MP-Slice Scalable Search\\ \hfill \\")
    indentor(file, 0, "Various Measurements}\n")

    indentor(file, 0, r"\begin{document}")
    indentor(file, 1, r"\frame{\titlepage")
    indentor(file, 2, r"\fontsize{5pt}{7pt}\selectfont")

    # title page information
    capture = ["Protocols", "Datatypes", "Inputs", "Preprocessing", "manipulate",
        "SplitRoles", "Pack", "Optimized", "SSL", "Function", "  Threads", 
        "txBuffer", "rxBuffer", "CPUS", "QUOTAS", "FREQS", "RAM",
        "LATENCIES", "BANDWIDTHS", "PACKETDROPS", "Summary file", "runtime"]
    with open(glob.glob(sevaredir + "E*-run-summary.dat")[0], "r") as f:
        for line in f:
            if "completed" in line:
                indentor(file, 2, r"Experiment run status: completed\\")
            elif "incomplete" in line:
                aborted = "_aborted"
                indentor(file, 2, r"Experiment run status: incomplete\\")
            elif "Nodes" in line:
                node = line.split(" ")[6]
                indentor(file, 2, line[:-1].replace("=", ":") + " (" + nodehardware[node] + ")" + r"\\")
            elif any(substring in line for substring in capture):
                indentor(file, 2, line[:-1].replace("_", "\\_").replace("=", ":") + r"\\")
                
            if "manipulate" in line and "6666" not in line:
                manipulation = "_" + line.strip().split(" ")[-1]

    indentor(file, 2, "Latex built date: " + time.strftime("%y.%m.%d %H:%M", time.gmtime()) + r"\\")
    indentor(file, 2, r"\vspace{50cm}")
    indentor(file, 1, "}")

    # Extended Experiment Information
    with open(glob.glob(sevaredir + "E*-run-summary.dat")[0], "r") as f:
        # Use a while loop to skip lines until we find the target line
        line = f.readline()
        while line:
            if "Networking Information" in line:
                break
            line = f.readline()

        # Only add frame, if information actually exists
        if line:
            indentor(file, 1, r"\begin{frame}[allowframebreaks]")
            indentor(file, 2, r"\fontsize{5pt}{7pt}\selectfont")
            indentor(file, 2, r"Experiment Networking Information\\")
            regex = r"total (sender|receiver) speed: ([0-9]+\.[0-9]+) Gbits/sec"
            speeds = []
            for line in f:
                # simply copy the info lines from summary to document
                indentor(file, 2, line.strip() + r"\\" if line != '\n' else r"\framebreak")
                # find the measured speeds to add to the filename
                match = re.search(regex, line)
                if match:
                    # extract the Gbit/s value and add it to the list
                    speeds.append(float(match.group(2)))

            if len(speeds) > 0:
                minspeed = "_" + str(min(speeds)).split(".")[0] + "Gbs"
            indentor(file, 1, r"\end{frame}")

    # Table of Contents page
    indentor(file, 1, r"\begin{frame}[allowframebreaks]{Outline}\fontsize{5pt}{7pt}\selectfont\tableofcontents\end{frame}" + "\n")

    # add all the plots
    for dir in sorted(os.listdir(sevaredir + "plotted/include")):
        indentor(file, 1, r"\section{" + dir[2:] + "}")
        for tex in sorted(os.listdir(sevaredir + "plotted/include/" + dir)):
            indentor(file, 2, r"\input{include/" + dir + "/" + tex[:-4] + "}")

    indentor(file, 0, "")
    indentor(file, 0, r"\end{document}")


os.chdir(sevaredir + "plotted")
print("Building latex file plotted/sevareplots.tex")
print("Please wait ... (Timeout set to 60s)")
try:
    with open("latex.log", "w") as file:
        subprocess.run(["pdflatex", "sevareplots.tex"], stdout=file, stderr=file, timeout=60)
        # run a second time for Table of Contents
        print("    First Latex Built success, running second build")
        subprocess.run(["pdflatex", "sevareplots.tex"], stdout=file, stderr=file, timeout=60)

except subprocess.TimeoutExpired:
    print("\nLatex Built failed. The output: (see latex.log for full log)\n")
    with open("latex.log", "r") as file:
        lines = file.readlines()
        for line in lines[-20:]:
            print(line.strip())

else:
    dateid = sevaredir.split("/")[-3][2:] + "-" + sevaredir.split("/")[-2][:-3]
    cpumodel = nodehardware[node].split(" ")[1].split("(")[0]

    positions = {}
    # add switch positions to the filename
    for switch in ["pre", "split", "pack", "opt", "ssl", "fun"]:
        for constellation in constellations:
            if switch in positions:
                if constellation[switch] not in positions[switch]:
                    positions[switch] += constellation[switch]
            else:
                positions[switch] = constellation[switch]
    # sort the switch positions for uniformity
    for switch, position in positions.items():
        positions.update({switch: ''.join(sorted(position))})

    switches = "_" + getConsString(positions) + manipulation
    pdfname = dateid + "_" + testtypes + cpumodel + minspeed + switches + aborted + ".pdf"
    print("Latex Built success:")
    print("    " + sevaredir + pdfname)
    # move pdf up
    subprocess.call(["mv", "sevareplots.pdf", "../" + pdfname])

subprocess.call(["mv", "latex.log", ".."])

# clean up the latex mess
for root, dirs, files in os.walk("."):
    for file in files:
        if file[-3:] in ["aux", "snm", "out", "log", "toc", "nav",]:
            os.remove(os.path.join(root, file))
