# Tools to extend the functionality of sevarebench

## Processing measurement results

After a benchmarking run with sevarebench, a folder containing the measurement results in a .csv file is generated. The following tools allow further processing of the collected data. For example, a successful sevarebench run like 

```
bash sevarebench.sh --experiment  --protocols 1,2,...,6 --nodes gard,goracle,zone --dtype 128,256 --bandwidth 25000,24500,...,8000 --split 0,1 --input 40960 &>> log &
```

generates a folder like "resultsMP-Slice/2023-02/01_17-01-02" and automatically uploads it to the installed upload git, in this case "repoupload: git@github.com:vyrovcz/sevaremeasurements.git" [github.com]https://github.com/vyrovcz/sevaremeasurements. The following tools operate with this direcory as parameter.

### sevare_parser.py

This tool extracts plot data from the results.csv file located in the results folder. On a client with the servareslice and -measurements gits cloned, a parsing routine example could look like this:

```
# On parsing server with required python modules, fetch results from git
cd sevaremeasurements
git pull
cd ..
# run parser
python3 sevareslice/tools/sevare_parser.py sevaremeasurements/resultsMP-Slice/2023-02/01_17-01-02
```

A new folder "parsed" appears in the results folder containing various plots.

### sevare_plotter_tex.py

This tool builds a document, visualizing all the plots in the previously generated "parsed" folder, offering various views on measurement results. On a client with the servareslice and -measurements gits cloned and a previously parsed results folder, a plotting routine example could look like this:

```
# run plotter
python3 sevareslice/tools/sevare_plotter_tex.py sevaremeasurements/resultsMP-Slice/2023-02/01_17-01-02
```

A new folder "plotted" appears in the results folder containing various latex files. Furthermore, the results folder now contains the generated .pdf document with all the charts.