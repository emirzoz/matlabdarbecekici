function saveProject(filename,db,tests,settings)
% Save the modal database, tests and the solve set-up (see vil.projectSettings).
if nargin < 3, tests = {}; end
if nargin < 4 || isempty(settings)
    db = vil.projectSettings(db); settings = db.config.settings;
end
save(filename,'db','tests','settings','-v7.3');
end
