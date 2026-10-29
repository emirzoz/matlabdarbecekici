function [geometry,info] = importCAD(filename,extraScale)
% Import a single-solid STEP or STL part as an fegeometry in metres.
% STEP files carry their own length unit and fegeometry converts them to
% metres on import (verified in R2025b: a 40 mm block imports as 0.04).
% Applying another 1e-3 scale shrinks the part 1000x, which was the cause of
% "no modes in band" for every imported STEP part. STL has no units, so its
% scale is guessed from the bounding box unless extraScale is given.
if nargin < 2 || isempty(extraScale), extraScale = "auto"; end
assert(~isempty(ver('pde')),'vil:NoPDE','VirtualImpactLab requires Partial Differential Equation Toolbox.');
filename = char(filename);
assert(isfile(filename),'vil:FileNotFound','File not found: %s',filename);
[~,name,ext] = fileparts(filename); ext = lower(ext);
info = struct('file',filename,'name',[name ext],'format',upper(ext(2:end)), ...
    'fileUnits',"unknown",'scaleApplied',1,'scaleNote',"");
switch ext
    case {'.step','.stp'}
        info.fileUnits = stepLengthUnit(filename);
        info.scaleNote = "STEP converted to metres by fegeometry using unit " + info.fileUnits + ".";
    case '.stl'
        info.fileUnits = "none (STL)";
    otherwise
        error('vil:Format','Unsupported CAD format %s. Use STEP (.step/.stp) or STL.',ext);
end
try
    geometry = fegeometry(filename);
catch err
    if contains(err.message,'solid')
        error('vil:NotSolid',['%s was read but MATLAB does not accept it as a closed solid ' ...
            '(%s). Re-export the part from CAD as a single solid body ' ...
            '(e.g. sew/heal the shell, remove assembly wrappers), or export an STL ' ...
            'and import that instead.'],info.name,err.message);
    end
    rethrow(err);
end
if geometry.NumCells ~= 1
    error('vil:MultiCell',['%s contains %d solid cells. Only one solid body is supported: ' ...
        'merge the bodies in CAD or export each part separately.'],info.name,geometry.NumCells);
end
span = boundingSpan(geometry);
if isstring(extraScale) || ischar(extraScale)
    extraScale = 1;
    if ext == ".stl" && max(span) > 2
        extraScale = 1e-3;
        info.scaleNote = "STL has no units; largest dimension > 2, so millimetres were assumed.";
    elseif ext == ".stl"
        info.scaleNote = "STL has no units; coordinates were taken as metres.";
    end
end
validateattributes(extraScale,{'numeric'},{'scalar','positive','finite'});
if extraScale ~= 1, geometry = scale(geometry,extraScale); end
info.scaleApplied = extraScale;
info.bboxMin = min(geometry.Vertices,[],1);
info.bboxMax = max(geometry.Vertices,[],1);
info.span = info.bboxMax-info.bboxMin;
info.numFaces = geometry.NumFaces;
info.numCells = geometry.NumCells;
if max(info.span) < 1e-3 || max(info.span) > 20
    warning('vil:Size','Part size %s m looks implausible; check the units.',mat2str(info.span,4));
end
end

function span = boundingSpan(g)
span = max(g.Vertices,[],1)-min(g.Vertices,[],1);
end

function unit = stepLengthUnit(filename)
% Read the declared length unit from the STEP header (first ~64 kB of DATA).
unit = "unknown";
fid = fopen(filename,'r'); if fid < 0, return; end
cleanup = onCleanup(@()fclose(fid));
txt = upper(string(fread(fid,[1 2e6],'*char')));
siTok = regexp(txt,'LENGTH_UNIT\s*\(\s*\)\s*NAMED_UNIT\s*\(\s*\*\s*\)\s*SI_UNIT\s*\(\s*(\.\w+\.|\$)\s*,\s*\.METRE\.','tokens','once');
if ~isempty(siTok)
    prefix = erase(siTok{1},".");
    map = dictionary(["$","MILLI","CENTI","DECI","KILO","MICRO"],["m","mm","cm","dm","km","um"]);
    if isKey(map,prefix), unit = map(prefix); else, unit = prefix + "m"; end
end
% Conversion-based units (e.g. INCH) must share an entity with LENGTH_UNIT;
% plane-angle units such as DEGREE are also conversion based.
conv = regexp(txt,'\(\s*CONVERSION_BASED_UNIT\s*\(\s*''(\w+)''[^;]*LENGTH_UNIT','tokens','once');
if isempty(conv)
    conv = regexp(txt,'LENGTH_UNIT[^;]*CONVERSION_BASED_UNIT\s*\(\s*''(\w+)''','tokens','once');
end
if ~isempty(conv), unit = lower(conv{1}); end
end
