# Original Author Philipp Eisermann 
# Original Source https://github.com/Philipp-Eisermann/sevareparser
# Adapted version
# testing with dir="sevaremeasurements/results/2022-08/09_07-59-42"

import argparse
import os
import subprocess

colors = ['black', 'blue', 'brown', 'cyan', 'darkgray', 'gray', 'green', 'lightgray', 'lime', 'magenta', 'olive',
          'orange', 'pink', 'purple', 'red', 'teal', 'violet', 'white', 'yellow']


# Is used to generate the axis labels of plots
def get_name(prefix_):
    prefix_names = ["datatype"] # Adaptions
    prefix_names += ["Latency (ms)", "Bandwidths (Mbit/s)", "Packet Loss (%)", "Frequency (GHz)", "Quotas(%)",
                    "CPU Threads", "Input Size"]  # Axis names
    prefixes_ = ["Dtp_"] # Adaptions
    prefixes_ += ["Lat_", "Bwd_", "Pdr_", "Frq_", "Quo_", "Cpu_", "Set_"]

    if prefix_ in prefixes_:
        return prefix_names[prefixes_.index(prefix_)]
    return prefix_


def generate_tex_plot(tex_name, exp_prefix, included_protocols):
    """
    Creates a .tex file for a single 2D plot
    :param tex_name: name of the tex file
    :param exp_prefix: prefix (giving the experiment variable(s)) of the datafile
    :param included_protocols: list of protocol names to be included in the plot
    // Path + prefix + included_protocol must point to the txt datafile of the protocol
    """
    path = "/parsed/2D/"
    tex_writer = open(tex_name, "w")
    tex_writer.write(r'\documentclass[8pt]{beamer}')

    tex_writer.write("\\setbeamertemplate{itemize item}{$-$}\n")
    tex_writer.write("\\usepackage{pgf}\n")
    tex_writer.write("\\usepackage{pgfplots}\n")
    tex_writer.write("\\pgfplotsset{compat=newest}\n\n")

    tex_writer.write("\\begin{document}\n\n")

    tex_writer.write("\\begin{frame}\n")
    # tex_writer.write("    \\frametitle{MP-Slice Runtimes Datatype -d 1}\n")
    tex_writer.write("    \\begin{figure}\n")
    tex_writer.write("        \\begin{tikzpicture}\n")
    tex_writer.write("            \\begin{axis}[\n")
    tex_writer.write("                xlabel={" + get_name(exp_prefix) + "}, ylabel={runtime [s]},legend style={anchor=west, legend pos=outer north east}]\n")

    for g in range(len(included_protocols)):
        tex_writer.write("                \\addplot[mark=|, color= " + colors[g] + ",   thick] table {../../../" + path + exp_prefix + included_protocols[g] + ".txt};\n")

    tex_writer.write("                \\legend{")

    for included_protocol in included_protocols:
        tex_writer.write(included_protocol + ",")

    tex_writer.write("}\n")
    tex_writer.write("            \\end{axis}\n")
    tex_writer.write("        \\end{tikzpicture}\n")

    tex_writer.write("        \\begin{itemize}\n")
    tex_writer.write("            \\item Ref.Problem: Scalable Search\n")
    tex_writer.write("            \\item Library: MP-Slice - Datatype -d 1\n")
    tex_writer.write("            \\item Metric: input size - runtime\n")
    tex_writer.write("            \\item Specs: D-1518(2.2GHz) 32GiB 1Gbits\n")
    tex_writer.write("        \\end{itemize}\n")

    tex_writer.write("    \\end{figure}\n")
    tex_writer.write("\\end{frame}\n")
    tex_writer.write("\\end{document}")

    tex_writer.close()

# - - - - - - - - ARGUMENTS - - - - - - - - - - -

parser = argparse.ArgumentParser(
    description='This program plots the results parsed by sevare parser.')

parser.add_argument('filename', type=str,
                    help='Required, name of the test-run folder (usually of the form MONTH-YEAR).')

args = parser.parse_args()

filename = args.filename

if filename[len(args.filename) - 1] != '/':
    filename += '/'

# - - - - - - - - - INIT  - - - - - - - - - - - - -
# Check if the parser was executed before
if "parsed" not in os.listdir(filename):
    print("Could not find the parsed directory, make sure you executed SevareParser before calling the plotter.")
    exit()

# Create directories
os.mkdir(filename + "plotted/")
os.mkdir(filename + "plotted/2D")

# - - - - - - - - CREATE 2D PLOTS - - - - - - - - - - -

data_names = os.listdir(filename + "parsed/2D/")

prefixes = []  # will contain the variables for 2D plotting
last = ""

print("Commencing 2D Plotting...")
# look at what variables were used in the experiment
for data in data_names:
    # only 2D files, so always 3 char long prefix for variable
    if last != data[0:4] and data[0] != '.':
        last = data[0:4]
        if last not in prefixes:
            prefixes += [last]
            # We want one directory for multiple graphs per variable
            # Its name should be the prefix without the tailing '_'
            os.mkdir(filename + "plotted/2D/" + last[:len(last) - 1])

# The runtime is in O(n*m) where n is # of protocols and m # of variables
# We need to go through all files for each variable to get all the datafiles for a variable to plot them together
for prefix in prefixes:
    # Will hold the filenames organized by security class for the prefix of this iteration
    protocols = [None] * 4
    for i in range(4):
        protocols[i] = []

    # sort in the 4 classes
    for data in data_names:
        if data[:4] == prefix:
            print(data)
            protocol_name = data[4:(len(data) - 4)]
            if get_security_class(protocol_name) == -1:
                print("- Protocol " + protocol_name + " not recognized.")
            else:
                print(protocol_name)
                protocols[get_security_class(protocol_name)] += [protocol_name]

    # create plots
    for i in range(4):  # for each security class
        if not protocols[i]:
            continue

        # Fill up info of this security class
        generate_tex_plot(filename + "plotted/2D/" + prefix[:len(last) - 1] + "/" + get_security_class_name(i) + ".tex", prefix, protocols[i])

        print("- saved: " + "plotted/2D/" + prefix[:len(last) - 1] + "/" + get_security_class_name(i) + ".tex")

# Make tex files and remove auxiliary files
os.chdir(filename + "plotted/2D/")
for prefix in prefixes:
    os.chdir(prefix)
    latex_files = os.listdir()
    for latex_file in latex_files:
        if not latex_file.endswith(".tex"):
            continue
        # Compile the LaTeX file
        subprocess.call(["pdflatex", latex_file])

        # Remove auxiliary files
        aux_files = [f for f in os.listdir() if (f.endswith(".aux") or f.endswith(".snm") or f.endswith(".out") or f.endswith(".log") or f.endswith(".toc") or f.endswith(".nav"))]
        for f in aux_files:
            os.remove(f)

    os.chdir("../")

os.chdir("../../../")

prefixes.remove("CostOfSecurity")

# Change exit() at check if 3D data exists if wanting to extend script!