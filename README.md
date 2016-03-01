# dyfi-summary
Data and programs for data processing yearly and cumulative summary maps for DYFI

===
Scripts to get cumulative peak intensity in each ZIP code over time, and plot the results. 
Will attempt to get DYFI Earthquake Catalog online instead of rerunning events.

Note: plotting function deprecated, send to Greg instead.

===
Usage:
---

summary_map.pl: Collects DYFI data and creates summary maps. 
Flags:
start		all events in the database (from 1990-?)
2015		only do this year
2015-01		only do this month
yearly		step through each year
monthly		step through each month and year
-noplot		deprecated, this flag is on by default
Other flags are available but deprecated (type 'summary_map.pl' without any flags)

redo_missing:
Reads the file 'missing_cdi.txt' and reruns ciimfast.pl on each event in it. (Note: no longer working, need to create ciimfast.pl)

xml2csv:
Converts XML input to CSV for faster upload

===
TODO:

Copy instances of required Perl modules (right now, requires symlink to DYFI perl/)
Check current year instead of hardcoding
Rewrite for Python DYFI


