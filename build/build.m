function build
% Minimal build script for GitHub Actions
% Works both locally and on a licensed runner

fprintf('MATLAB %s\n', version);
projRoot = fileparts(mfilename('fullpath'));
repoRoot = fileparts(projRoot);
cd(repoRoot);

outDir = fullfile(projRoot,'output');
if ~exist(outDir,'dir'), mkdir(outDir); end

% Package standalone app (adjust paths/filenames as needed)
exe = compiler.build.standaloneApplication( ...
    'run_ktrhfs_app.m', ...
    'ExecutableName','KTRHFSBatch', ...
    'AdditionalFiles',{'KTRHFSBatchApp.m','assets/Cardiac Tissue Mechanics Analyzer.png'}, ...
    'OutputDir',outDir);

% Optionally create an installer
try
    compiler.package.installer(exe,'ApplicationName','KTR/HFS Batch Reviewer', ...
        'RuntimeDelivery','web', 'OutputDir', outDir);
catch ME
    warning('Installer packaging skipped: %s', ME.message);
end

disp('Build complete.');
end

