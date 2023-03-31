# Original Author Philipp Eisermann 
# Original Source https://github.com/Philipp-Eisermann/sevareparser
# Adapted version

import argparse
import os

# custom imports
import re
import glob
import subprocess

# SEVARE PARSER 2.0 - adapted to new table format
# Format of short datatable:
#
# program;c.domain;adv.model;protocol;partysize;comp.time(s);comp.peakRAM(MiB);bin.filesize(MiB);input_size;runtime_internal(s);runtime_external(s);peakRAM(MiB);jobCPU(%);P0commRounds;P0dataSent(MB);ALLdataSent(MB)
#   0         1       2         3         4          5               6                7            8 + n        9 + n                  10 + n          11 + n      12 + n     13 + n

# REQUIREMENTS:
# - The table MUST NOT contain lines with equal values of the variable array (see variable_array) - this only happens
# if the protocol was run multiple times for same parameter values in the same run


# ----- ARGUMENTS --------
parser = argparse.ArgumentParser(
    description='This program parses the measurement folder outputted by sevareslice (version from 03/23).')

parser.add_argument('data_dir', type=str, help='Required, testresults dir to parse.')
parser.add_argument('-s', type=str, help='(Optional) Sort table by <parameter> (3D parsing)')
parser.add_argument('-f', "--force", action="store_true", help='(Optional) Force overwrite')

args = parser.parse_args()

data_dir = args.data_dir

if data_dir[len(args.data_dir)-1] != '/':
    data_dir += '/'

# ------- PARSING ---------

# Open datatable
data_table = None
for file in sorted(os.listdir(data_dir + 'data/')):
    if file.endswith(".csv") and ("full" in file or "short" in file):
        print("Found results table...")
        data_table = file
        break

if data_table is None:
    print("Could not find a csv file with 'full' or 'short' in the name.")
    exit()

data_table = open(data_dir + 'data/' + data_table)

if os.path.exists(data_dir + "parsed"):
    if not args.force:
        print("Error, \"parsed\"-folder exits. Run parser with -f to force overwriting")
        exit()

    subprocess.run(["rm", "-rf", data_dir + "parsed"])

os.mkdir(data_dir + "parsed")


#runtimes_file_2D = open(data_dir + "parsed/runtimes2D.txt", "a")
#info_file = open(data_dir + "parsed/protocol_infos.txt", "a")

header = data_table.readline().split(';')

runtime_index = -1
protocol_index = -1
sorting_index = -1

comm_rounds_index = -1
data_sent_index = -1

# datatype and inputsize must stay at position [0] and [-1] to work, add new vars inbetween
variable_array = ["datatype", "threads", "txbuffer", "rxbuffer"] # Adaptions
variable_array += ["latencies(ms)", "bandwidths(Mbs)", "packetdrops(%)", "freqs(GHz)", "quotas(%)", "cpus", "input_size"]  # Names from the table!
var_name_array = ["Dtp_", "Thd_", "txB_", "rxB_"] # Adaptions
var_name_array += ["Lat_", "Bwd_", "Pdr_", "Frq_", "Quo_", "Cpu_", "Inp_"]  # INDICES HAVE TO MATCH ABOVE ARRAY
var_val_array = [None] * len(variable_array)  # used to store changing variables
index_array = [-1] * len(variable_array)
datafile_array = [None] * len(variable_array)

# Adaption
# switches are on/off values, where a feature is either off or on
# e -> preprocess; r -> splitroles; c -> packbool; o -> optimize sharing; h -> ssl; f -> function;
switches_names = ["preprocess", "splitroles", "packbool", "optshare", "ssl", "function"]
switch_indexes = [-1] * len(switches_names)

# Get indexes of present columns
for i in range(len(header)):
    # Indexes of variables
    for j in range(len(index_array)):
        if header[i] == variable_array[j]:
            index_array[j] = i
    
     # Adaptions: Indexes of switches
    for j in range(len(switch_indexes)):
        if header[i] == switches_names[j]:
            switch_indexes[j] = i

    if header[i] == "runtime_chrono(s)":  # Name from the table
        runtime_index = i
    elif header[i] == "protocol":  # Name from the table
        protocol_index = i
    # Sorting index
    elif header[i] == args.s:
        sorting_index = i
    # Metrics indexes
    elif header[i] == "P0dataSent(MB)":
        comm_rounds_index = i
    elif header[i] == "ALLdataSent(MB)":  # "P0dataSent(MB)"
        data_sent_index = i

if not os.path.exists(data_dir + "parsed/2D"):
    os.mkdir(data_dir + "parsed/2D")

#if not os.path.exists(data_dir + "parsed/3D"):
#    os.mkdir(data_dir + "parsed/3D")

# Create array of dataset
protocol = ""
protocols = []
comm_rounds_array = []
data_sent_array = []

previous = ""

dataset_array = []
for row in data_table.readlines():
    dataset_array.append(row.split(';'))

# Needs to be sorted by protocol, MPSlice exporting order is different
dataset_array = sorted(dataset_array, key=lambda x: x[protocol_index])
## debug
##for row in dataset_array:
##    print(" ".join("{:4}".format(col) for col in row), end = " ")

# get highest input value from summary
maxinput = -1
maxdtype = -1
with open(glob.glob(data_dir + "E*-run-summary.dat")[0], "r") as f:
    for line in f:
        match = re.search(r"Inputs.*", line)
        if match:
            numbers = [int(x) for x in re.findall(r'\b\d+\b', match.group(0))]
            maxinput = max(numbers)
        match = re.search(r"Datatypes.*", line)
        if match:
            numbers = [int(x) for x in re.findall(r'\b\d+\b', match.group(0))]
            maxdtype = max(numbers)    

# - - - - - - - Parsing for 2D plots - - - - - - - -
# Go through dataset for each variable
print(index_array)
for i in range(len(index_array)):
    # Only parse for variables that are measured in the table
    if index_array[i] == -1:
        continue

    # print(str(i) + " Iteration")
    # If table only contains one protocol
    protocol = None

    for line in dataset_array:
        # Sometimes the last line of the table is \n
        if line[0] == "\n":
            continue

        # When a new protocol is parsed
        if protocol != line[protocol_index]:
            # Update protocol
            protocol = line[protocol_index]
            protocols.append(protocol)

            if not os.path.exists(data_dir + "parsed/2D/" + protocol):
                os.mkdir(data_dir + "parsed/2D/" + protocol)

            # Fill up the var_val array with initial values of every other configured parameter - have to be fix (controlled variables)
            # skip the input size, found in previous step
            for j in range(len(index_array)):
                if index_array[j] != -1 and i != j:
                    if j > 0 and j < len(index_array) - 1:
                        var_val_array[j] = line[index_array[j]]
                    elif j > 0:
                        var_val_array[-1] = maxinput # Adapt: fix to highest input
                    else:
                        var_val_array[0] = maxdtype  # Adapt: fix to highest dtype
                else:
                    var_val_array[j] = None  # may be inefficient
            print(protocol + " " +  str(var_name_array[i]) + " " +  str(var_val_array))

            # Fill up metrics arrays
            comm_rounds_array.append(line[comm_rounds_index])
            data_sent_array.append(line[data_sent_index])

        # default values in case the table is lacking them
        pre = line[switch_indexes[0]] if switch_indexes[0] > 0 else 0
        split = line[switch_indexes[1]] if switch_indexes[1] > 0 else 0
        pack = line[switch_indexes[2]] if switch_indexes[2] > 0 else 0
        opt = line[switch_indexes[3]] if switch_indexes[3] > 0 else 1
        ssl = line[switch_indexes[4]] if switch_indexes[4] > 0 else 1
        function = line[switch_indexes[5]] if switch_indexes[5] > 0 else 0
        # we want all dtypes for variable input, so special case if handling input size
        if i == len(index_array) - 1:
            dtype = line[index_array[0]]
            var_val_array[0] = None
        else:
            dtype = str(var_val_array[0]) if var_val_array[0] != None else "all"
        # path of form parsed/2D/p1/d128Bwd_pre0split0pack0opt1ssl1fun0.txt
        txtpathbase = data_dir + "parsed/2D/" + protocol + "/" + "d" + dtype + "_" + str(var_name_array[i])
        txtpath = txtpathbase + "pre" + str(pre) + "split" + str(split) + "pack" + str(pack) + "opt" + str(opt) + "ssl" + str(ssl) + "fun" + str(function) + ".txt"
        if txtpath != previous :
            # Create 2D file descriptor
            datafile2D = open(txtpath, "a", 1)
            previous = txtpath

        # Only parse line when it shows the initial values of controlled variables
        #print(str([str(var_val_array[j]) + "  " + line[index_array[j]] for j in range(len(index_array))]) + " " + line[runtime_index])
        #print([var_val_array[j] is None or int(var_val_array[j]) == int(line[index_array[j]]) for j in range(len(index_array))])
        if all((var_val_array[j] is None or float(var_val_array[j]) == float(line[index_array[j]])) for j in range(len(index_array))):
            datafile2D.write(line[index_array[i]] + '\t' + line[runtime_index] + '\n')

datafile2D.close()
