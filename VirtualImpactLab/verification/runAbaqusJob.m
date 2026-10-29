function abq = runAbaqusJob(inpFile,opts)
% Run an Abaqus/Standard input file and read its results back into MATLAB.
% Desktop only (MATLAB Online cannot reach a local Abaqus installation).
arguments
    inpFile (1,1) string
    opts.Abaqus (1,1) string = abaqusCommand()
    opts.Cpus (1,1) double = 4
end
[folder,job] = fileparts(inpFile);
here = cd(folder); restore = onCleanup(@()cd(here));
status = system(sprintf('"%s" job=%s input=%s cpus=%d interactive ask_delete=OFF', ...
    opts.Abaqus,job,job+".inp",opts.Cpus));
odb = fullfile(folder,job+".odb");
assert(status==0 && isfile(odb),'vil:Abaqus','Abaqus job %s failed; see %s.',job,fullfile(folder,job+".dat"));
out = fullfile(folder,job+"_results");
reader = fullfile(fileparts(mfilename('fullpath')),'abaqus','read_odb.py');
status = system(sprintf('"%s" python "%s" "%s" "%s"',opts.Abaqus,reader,odb,out));
% abaqus python exits 0 even when the script raises, so check its output.
assert(status==0 && isfile(fullfile(out,'frequencies.txt')),'vil:AbaqusRead','Reading %s failed.',odb);
abq = readAbaqusResults(out);
end

function cmd = abaqusCommand()
cmd = "C:\SIMULIA\Commands\abaqus.bat";
if ~isfile(cmd), cmd = "abaqus"; end
end
