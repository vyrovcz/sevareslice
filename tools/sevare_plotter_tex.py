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
nodehardware.update({node: "D-1518(2.2GHz) 32GiB 1Gbits" for node in ["dogecoin", "bitcoin", "ether", "todd", "rod", "ned"]})
nodehardware.update({node: "7543(2.8GHz) 512GiB 25Gbits" for node in ["gard", "goracle", "zone"]})
nodehardware.update({node: "6312U(2.4GHz) 512GiB 25Gbits" for node in ["meld", "yieldly", "tinyman"]})

legenddict = {
    "1": "Sharemind",
    "2": "Replicated",
    "3": "Astra",
    "4": "OEC DUP",
    "5": "OEC REP",
    "6": "TTP",
    "d1": "bool",
    "d8": "char",
    "d64": "uint64",
    "d128": "SSE",
    "d256": "AVX",
    "d512": "AVX512"
}

def get_Specs(path):
    with open(glob.glob(path.split("plotted")[0] + "E*-run-summary.dat")[0], "r") as f:
        for line in f:
            match = re.search(r"Nodes.*", line)
            if match:
                return nodehardware[match.group(0).split(" ")[2]]

# Is used to generate the axis labels of plots
def get_name(prefix_):
    prefix_names = ["Datatype [bits]"] # Adaptions
    prefix_names += ["Latency [ms]", "Bandwidths [Mbit/s]", "Packet Loss [%]", "Frequency [GHz]", "Quotas [%]",
                    "CPU Threads", "Input Size"]  # Axis names
    prefixes_ = ["Dtp_"] # Adaptions
    prefixes_ += ["Lat_", "Bwd_", "Pdr_", "Frq_", "Quo_", "Cpu_", "Inp_"]

    if prefix_ in prefixes_:
        return prefix_names[prefixes_.index(prefix_)]
    return prefix_

def indentor(file, indentation_level, text):
    file.write(textwrap.indent(text, prefix=" " * 4 * indentation_level) + os.linesep)

def getConsString(constellation):
    return "pre" + constellation["pre"] + "split" + constellation["split"] + "pack" + constellation["pack"] + "opt" + constellation["opt"]

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
        indentor(file, 0, "%% Build with sevareparser on day %%")
        indentor(file, 0, "%%      " + time.strftime("%d %B %Y", time.gmtime()) + "      %%")
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
            print("    " + plotpath)
            divisor = plots[g].split("/")[1][1:]
            divisor = divisor if isinstance(divisor, int) else "1"
            dtypeNorm =  r" [y expr=\thisrowno{1} / " + divisor + "] "
            indentor(file, 3, r"\addplot[mark=|, thick, color=" + colors[g] + "] table" + dtypeNorm + " {" + plotpath + "};")
        
        mode = 1 if datatypemode else 0
        #print([plot.split("/") for plot in plots])
        indentor(file, 3, r"\legend{" + ', '.join([legenddict[key.split("/")[mode]] for key in plots ]) + "}")
        indentor(file, 2, r"\end{axis}")
        indentor(file, 1, r"\end{tikzpicture}")

        indentor(file, 1, r"\begin{itemize}")
        indentor(file, 1, r"\item Ref.Problem: Scalable Search")
        indentor(file, 1, r"\item Library: MP-Slice - " + name + " (" + legenddict[name.split(" ")[-1]] + ")")
        indentor(file, 1, r"\item Metric: " + get_name(exp_prefix).split("[")[0] + " - runtime")
        switchpositions = "Preprocessing: " + constellation["pre"] + ", Split Roles: " + constellation["split"]
        switchpositions += ", Pack Bool: " + constellation["pack"] + ", Optimize Sharing: " + constellation["opt"]
        indentor(file, 1, r"\item Switches: " + switchpositions)
        indentor(file, 1, r"\item Specs: " + get_Specs(tex_name))
        indentor(file, 1, r"\end{itemize}")

        indentor(file, 0, r"\end{figure}")
        indentor(file, 0, r"\end{frame}")

# - - - - - - - - ARGUMENTS - - - - - - - - - - -

parser = argparse.ArgumentParser(
    description='This program plots the results parsed by sevare parser.')

parser.add_argument('sevaredir', type=str,
                    help='Required, name of the test-run folder (usually of the form MONTH-YEAR).')

args = parser.parse_args()

sevaredir = args.sevaredir

if sevaredir[-1] != '/':
    sevaredir += '/'

# - - - - - - - - - INIT  - - - - - - - - - - - - -
# Check if the parser was executed before
if "parsed" not in os.listdir(sevaredir):
    print("Could not find the parsed directory, make sure you executed SevareParser before calling the plotter.")
    exit()

# Create directories
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
    for switch, position in re.findall(r'([A-Za-z]+)([01])', plot.split("_")[2][:-4]):
        constellation[switch] = position
    constellations.append(constellation)

# remove duplicates
prefixes = [i for n, i in enumerate(prefixes) if i not in prefixes[:n]]
constellations = [i for n, i in enumerate(constellations) if i not in constellations[:n]]
datatypes = [i for n, i in enumerate(datatypes) if i not in datatypes[:n]]
datatypes = sorted(datatypes)

# get highest input value from summary
maxinput = -1
maxdtype = -1
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
print(datatypes)
print(prefixes)
print(constellations)
print(getConsString(constellations[0]))
print(protocols)
print(plots)
print()

# generate .tex files into an "include" folder
os.mkdir(sevaredir + "plotted/include")

## inputsize - runtime (should be always true)
######

if "Inp" not in prefixes:
    print("No *_Inp_* found, should exist in any correctly parsed folder")
    exit()

os.mkdir(sevaredir + "plotted/include/input")

# protocol view
for constellation in constellations:
    for protocol in protocols:
        plots = [protocol + "/" + datatype for datatype in datatypes]
        savepath = sevaredir + "plotted/include/input/s" + protocol + "_" + getConsString(constellation) + ".tex"
        genTex(savepath, "Inp_", plots, " Protocol -s " + protocol, constellation, 1)
        print("- saved: plotted/include/input/s" + protocol + "_" + getConsString(constellation) + ".tex")

# datatype view
for constellation in constellations:
    for datatype in datatypes:
        plots = [protocol + "/" + datatype for protocol in protocols]
        savepath = sevaredir + "plotted/include/input/" + datatype + "_" + getConsString(constellation) + ".tex"
        genTex(savepath, "Inp_", plots, " Datatype -d " + datatype, constellation)
        print("- saved: plotted/include/input/" + datatype + "_" + getConsString(constellation) + ".tex")

os.mkdir(sevaredir + "plotted/include/manipulations")

## fixed input views
######
# datatypes
for constellation in constellations:
    plots = [protocol + "/dall" for protocol in protocols]
    savepath = sevaredir + "plotted/include/manipulations/dall" + "_" + getConsString(constellation) + ".tex"
    genTex(savepath, "Dtp_", plots, "Fixed Input: " + str(maxinput) + " -d " + datatype, constellation)
    print("- saved: plotted/include/manipulations/dall" + "_" + getConsString(constellation) + ".tex")


# bandwidth
for prefix in ["Lat_", "Bwd_", "Pdr_", "Frq_", "Quo_", "Cpu_"]:
    if not fileExists(sevaredir + "parsed/2D/" + protocols[0], prefix):
        continue
    for constellation in constellations:
        plots = [protocol + "/d" + str(maxdtype) for protocol in protocols]
        savepath = sevaredir + "plotted/include/manipulations/d" + str(maxdtype) + "_" + prefix + getConsString(constellation) + ".tex"
        genTex(savepath, prefix, plots, "Fixed Input: " + str(maxinput) + " -d " + datatype, constellation)
        print("- saved: plotted/include/manipulations/d" + str(maxdtype) + "_" + prefix + getConsString(constellation) + ".tex")


### build main tex file
with open(sevaredir + "plotted/sevareplots.tex", "w") as file:
    indentor(file, 0, "%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%")
    indentor(file, 0, "%% Build with sevareparser on day")
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
    indentor(file, 1, r"\frame {")
    indentor(file, 2, r"\titlepage")
    indentor(file, 1, "}\n")

    for dir in os.listdir(sevaredir + "plotted/include"):
        for tex in os.listdir(sevaredir + "plotted/include/" + dir):
            indentor(file, 1, r"\include{include/" + dir + "/" + tex[:-4] + "}")
    indentor(file, 0, "")
    indentor(file, 0, r"\end{document}")


os.chdir(sevaredir + "plotted")
#print(os.getcwd())
print("Building latex file plotted/sevareplots.tex")
print("Please wait ... (Timeout set to 60s)")
try:
    with open("latexlog", "w") as file:
        sprun = subprocess.run(["pdflatex", "sevareplots.tex"], stdout=file, stderr=file, timeout=60)

except subprocess.TimeoutExpired:
    print("\nLatex Build failed. The output:\n")
    with open("latexlog", "r") as file:
        lines = file.readlines()
        for line in lines[-20:]:
            print(line.strip())

else:
    pdfname="sevareplots_" + time.strftime("%y.%m.%d_%H.%M.%S", time.gmtime()) + ".pdf"
    print("Latex Build success:")
    print("    " + sevaredir + pdfname)
    # move pdf up
    subprocess.call(["mv", "sevareplots.pdf", "../" + pdfname])

# clean up the latex mess
for root, dirs, files in os.walk("."):
    for file in files:
        if file[-3:] in ["aux", "snm", "out", "log", "toc", "nav",]:
            os.remove(os.path.join(root, file))
