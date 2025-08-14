classdef KTRHFSBatchApp < matlab.apps.AppBase
    %% ================== UI HANDLES ==================
    properties (Access = private)
        UIFigure             matlab.ui.Figure
        Grid                 matlab.ui.container.GridLayout

        % top row
        SelectParentButton   matlab.ui.control.Button
        ParentPathLabel      matlab.ui.control.Label
        StartButton          matlab.ui.control.Button
        ModeLabel            matlab.ui.control.Label
        ModeDropDown         matlab.ui.control.DropDown
        FolderStatusLabel    matlab.ui.control.Label
        QuitButton           matlab.ui.control.Button     % <-- NEW

        % record row
        RecordIdxLabel       matlab.ui.control.Label
        T1Label              matlab.ui.control.Label
        T1Field              matlab.ui.control.NumericEditField
        T2Label              matlab.ui.control.Label
        T2Field              matlab.ui.control.NumericEditField
        T3Label              matlab.ui.control.Label
        T3Field              matlab.ui.control.NumericEditField

        % tabs
        TabGroup             matlab.ui.container.TabGroup
        TabKTR               matlab.ui.container.Tab
        TabHFS               matlab.ui.container.Tab

        % axes
        Ax                   matlab.ui.control.UIAxes
        AxFFT                matlab.ui.control.UIAxes

        % fixed control bars
        KCtrlGrid            matlab.ui.container.GridLayout
        HCtrlGrid            matlab.ui.container.GridLayout

        % KTR controls
        PrevButton           matlab.ui.control.Button
        DoneNextButton       matlab.ui.control.Button
        SkipFileButton       matlab.ui.control.Button
        SkipFolderButton     matlab.ui.control.Button
        ForceLabel           matlab.ui.control.Label
        ForceValLabel        matlab.ui.control.Label
        KtrLabel             matlab.ui.control.Label
        KtrValLabel          matlab.ui.control.Label

        % HFS controls
        HFSPrevButton        matlab.ui.control.Button
        HFSNextButton        matlab.ui.control.Button
        HFSFinishButton      matlab.ui.control.Button
        HFSIdxLabel          matlab.ui.control.Label
        HFSParamLabel        matlab.ui.control.Label
        HFSParamValLabel     matlab.ui.control.Label

        % bottom readouts
        F0Label              matlab.ui.control.Label
        F0ValLabel           matlab.ui.control.Label

        % status log
        StatusArea           matlab.ui.control.TextArea
    end

    %% ================== APP STATE ==================
    properties (Access = private)
        % batch
        parentDir   char
        subDirs     string
        iFolder     double = 0
        folderName  char

        % per folder data
        dats_ktr    cell
        dats_hfs    cell

        % KTR state
        j           double = 1
        cache       cell
        tmarks      double
        ktr_all     double
        force_all   double
        f0_all      double
        vLines      cell
        fitLine     matlab.graphics.chart.primitive.Line

        % HFS state
        hfs_j       double = 1
        hfs_param   double
        hfs_f       cell
        hfs_mag     cell
        hfs_peakf   double

        % constants
        t4          double = 4.0
        guessT      double = [0.5073, 0.5149, 0.5295]

        % quitting / progress
        StopFlag    logical = false        % <-- NEW
        ProgDlg                                 % <-- NEW (uiprogressdlg handle)
    end

    %% ================== CONSTRUCTOR ==================
    methods (Access = public)
        function app = KTRHFSBatchApp
            % Persistent splash until Continue
            splashPath = app.resourcePath('assets','Cardiac Tissue Mechanics Analyzer.png');
            W = 680; H = 440;
            if isfile(splashPath)
                s = uifigure('Name','Welcome','Position',[100 100 W H], ...
                             'Resize','off','WindowStyle','modal','Icon',splashPath);
            else
                s = uifigure('Name','Welcome','Position',[100 100 W H], ...
                             'Resize','off','WindowStyle','modal');
            end
            g = uigridlayout(s,[4,1]); g.RowHeight={'1x',24,40,16}; g.ColumnWidth={'1x'};
            if isfile(splashPath)
                uiimage(g,'ImageSource',splashPath,'ScaleMethod','fit');
            else
                uilabel(g,'Text','KTR/HFS Batch Reviewer','FontSize',18,'FontWeight','bold','HorizontalAlignment','center');
            end
            uilabel(g,'Text','Click Continue to start','HorizontalAlignment','center');
            uibutton(g,'Text','Continue','FontSize',14,'ButtonPushedFcn',@(btn,evt) uiresume(s));
            s.CloseRequestFcn = @(~,~) uiresume(s);
            uiwait(s); if isvalid(s), delete(s); end

            app.createComponents();
        end

        function waitUntilClosed(app)
            waitfor(app.UIFigure);
        end
    end

    %% ================== PATH HELPER ==================
    methods (Access = private)
        function p = resourcePath(~, varargin)
            if isdeployed
                base = ctfroot;
            else
                base = fileparts(which('KTRHFSBatchApp'));
                if isempty(base), base = pwd; end
            end
            p = fullfile(base, varargin{:});
        end
    end

    %% ================== UI SETUP ==================
    methods (Access = private)
        function createComponents(app)
            app.UIFigure = uifigure('Name','KTR/HFS Batch Reviewer','Position',[80 80 1240 780]);
            ico = app.resourcePath('assets','Cardiac Tissue Mechanics Analyzer.png');
            if isfile(ico), app.UIFigure.Icon = ico; end

            app.Grid = uigridlayout(app.UIFigure,[8,8]);
            app.Grid.RowHeight   = {30,30,30,'1x',40,24,120,30};
            app.Grid.ColumnWidth = {130,130,110,140,'1x',110,110,130};

            % Row 1
            app.SelectParentButton = uibutton(app.Grid,'Text','Select Parent…','ButtonPushedFcn',@app.onSelectParent);
            app.SelectParentButton.Layout.Row=1; app.SelectParentButton.Layout.Column=1;

            app.ParentPathLabel = uilabel(app.Grid,'Text','(no folder selected)');
            app.ParentPathLabel.Layout.Row=1; app.ParentPathLabel.Layout.Column=[2 8];

            % Row 2
            app.StartButton = uibutton(app.Grid,'Text','Start','ButtonPushedFcn',@app.onStart);
            app.StartButton.Layout.Row=2; app.StartButton.Layout.Column=1;

            app.ModeLabel = uilabel(app.Grid,'Text','Mode:','HorizontalAlignment','right');
            app.ModeLabel.Layout.Row=2; app.ModeLabel.Layout.Column=2;
            app.ModeDropDown = uidropdown(app.Grid,'Items',{'Interactive','Auto (default t)'},'Value','Interactive');
            app.ModeDropDown.Layout.Row=2; app.ModeDropDown.Layout.Column=3;

            app.FolderStatusLabel = uilabel(app.Grid,'Text','Folder: 0 / 0');
            app.FolderStatusLabel.Layout.Row=2; app.FolderStatusLabel.Layout.Column=[4 7];   % <-- freed col 8

            app.QuitButton = uibutton(app.Grid,'Text','Quit','ButtonPushedFcn',@app.onQuit); % <-- NEW
            app.QuitButton.Layout.Row = 2; app.QuitButton.Layout.Column = 8;

            % Row 3
            app.RecordIdxLabel = uilabel(app.Grid,'Text','Record: — / —');
            app.RecordIdxLabel.Layout.Row=3; app.RecordIdxLabel.Layout.Column=1;

            app.T1Label = uilabel(app.Grid,'Text','t1 (s):','HorizontalAlignment','right');
            app.T1Label.Layout.Row=3; app.T1Label.Layout.Column=4;
            app.T1Field = uieditfield(app.Grid,'numeric','ValueChangedFcn',@(s,e)app.onEditMark(1));
            app.T1Field.Layout.Row=3; app.T1Field.Layout.Column=5;

            app.T2Label = uilabel(app.Grid,'Text','t2 (s):','HorizontalAlignment','right');
            app.T2Label.Layout.Row=3; app.T2Label.Layout.Column=6;
            app.T2Field = uieditfield(app.Grid,'numeric','ValueChangedFcn',@(s,e)app.onEditMark(2));
            app.T2Field.Layout.Row=3; app.T2Field.Layout.Column=7;

            app.T3Label = uilabel(app.Grid,'Text','t3 (s):','HorizontalAlignment','right');
            app.T3Label.Layout.Row=3; app.T3Label.Layout.Column=8;
            app.T3Field = uieditfield(app.Grid,'numeric','ValueChangedFcn',@(s,e)app.onEditMark(3));
            app.T3Field.Layout.Row=3; app.T3Field.Layout.Column=8;

            app.T1Field.Limits = [-Inf Inf]; app.T2Field.Limits = [-Inf Inf]; app.T3Field.Limits = [-Inf Inf];
            app.T1Field.Enable='off'; app.T2Field.Enable='off'; app.T3Field.Enable='off';

            % Row 4: tabs
            app.TabGroup = uitabgroup(app.Grid,'SelectionChangedFcn',@app.onTabChanged);
            app.TabGroup.Layout.Row=4; app.TabGroup.Layout.Column=[1 8];

            app.TabKTR = uitab(app.TabGroup,'Title','KTR Trace');
            gK = uigridlayout(app.TabKTR,[1,1]); gK.RowHeight={'1x'}; gK.ColumnWidth={'1x'};
            app.Ax = uiaxes(gK); app.Ax.Layout.Row=1; app.Ax.Layout.Column=1;
            xlabel(app.Ax,'Time (s)'); ylabel(app.Ax,'Tension (mN/mm^2)'); grid(app.Ax,'on');

            app.TabHFS = uitab(app.TabGroup,'Title','HFS FFT');
            gH = uigridlayout(app.TabHFS,[1,1]); gH.RowHeight={'1x'}; gH.ColumnWidth={'1x'};
            app.AxFFT = uiaxes(gH); app.AxFFT.Layout.Row=1; app.AxFFT.Layout.Column=1;
            xlabel(app.AxFFT,'Frequency (Hz)'); ylabel(app.AxFFT,'|Z(f)|'); grid(app.AxFFT,'on');

            % Row 5: control bars
            app.KCtrlGrid = uigridlayout(app.Grid,[1,9]);
            app.KCtrlGrid.Layout.Row=5; app.KCtrlGrid.Layout.Column=[1 8];
            app.KCtrlGrid.ColumnWidth = {100,140,100,120,'1x',110,80,90,80};

            app.PrevButton       = uibutton(app.KCtrlGrid,'Text','◀ Prev','ButtonPushedFcn',@app.onPrev);              app.PrevButton.Layout.Column=1;
            app.DoneNextButton   = uibutton(app.KCtrlGrid,'Text','Done → Next','ButtonPushedFcn',@app.onDoneNext);     app.DoneNextButton.Layout.Column=2;
            app.SkipFileButton   = uibutton(app.KCtrlGrid,'Text','Skip File','ButtonPushedFcn',@app.onSkipFile);       app.SkipFileButton.Layout.Column=3;
            app.SkipFolderButton = uibutton(app.KCtrlGrid,'Text','Skip Folder','ButtonPushedFcn',@app.onSkipFolder);   app.SkipFolderButton.Layout.Column=4;

            app.ForceLabel    = uilabel(app.KCtrlGrid,'Text','Force (mN/mm^2):','HorizontalAlignment','right');        app.ForceLabel.Layout.Column=6;
            app.ForceValLabel = uilabel(app.KCtrlGrid,'Text','—','HorizontalAlignment','right');                        app.ForceValLabel.Layout.Column=7;
            app.KtrLabel      = uilabel(app.KCtrlGrid,'Text','ktr (1/s):','HorizontalAlignment','right');              app.KtrLabel.Layout.Column=8;
            app.KtrValLabel   = uilabel(app.KCtrlGrid,'Text','—','HorizontalAlignment','right');                        app.KtrValLabel.Layout.Column=9;

            app.HCtrlGrid = uigridlayout(app.Grid,[1,6]);
            app.HCtrlGrid.Layout.Row=5; app.HCtrlGrid.Layout.Column=[1 8];
            app.HCtrlGrid.ColumnWidth = {100,120,180,'1x',100,160};
            app.HCtrlGrid.Visible = 'off';

            app.HFSPrevButton   = uibutton(app.HCtrlGrid,'Text','◀ Prev','ButtonPushedFcn',@app.onHFSPrev);            app.HFSPrevButton.Layout.Column=1;
            app.HFSNextButton   = uibutton(app.HCtrlGrid,'Text','Next ▶','ButtonPushedFcn',@app.onHFSNext);            app.HFSNextButton.Layout.Column=2;
            app.HFSFinishButton = uibutton(app.HCtrlGrid,'Text','Save & Next Folder','ButtonPushedFcn',@app.onHFSFinish); app.HFSFinishButton.Layout.Column=3;
            app.HFSIdxLabel     = uilabel(app.HCtrlGrid,'Text','HFS: — / —');                                          app.HFSIdxLabel.Layout.Column=5;
            app.HFSParamLabel   = uilabel(app.HCtrlGrid,'Text','HFFTS:','HorizontalAlignment','right');                 app.HFSParamLabel.Layout.Column=6;
            app.HFSParamValLabel= uilabel(app.HCtrlGrid,'Text','—');                                                    app.HFSParamValLabel.Layout.Column=6;

            % Row 6: f0 baseline
            app.F0Label    = uilabel(app.Grid,'Text','f0 baseline:','HorizontalAlignment','right');
            app.F0Label.Layout.Row=6; app.F0Label.Layout.Column=5;
            app.F0ValLabel = uilabel(app.Grid,'Text','—'); app.F0ValLabel.Layout.Row=6; app.F0ValLabel.Layout.Column=6;

            % Row 7: Status log
            app.StatusArea = uitextarea(app.Grid,'Editable','off','Value',{'Ready.'});
            app.StatusArea.Layout.Row=7; app.StatusArea.Layout.Column=[1 8];

            % Row 8: key handler
            app.UIFigure.WindowKeyPressFcn = @(~,evt) app.onKeyNudge(evt);
        end
    end

    %% ================== EVENT HANDLERS ==================
    methods (Access = private)
        function onSelectParent(app,~,~)
            d = uigetdir();
            if isequal(d,0), return; end
            app.parentDir = d;
            app.ParentPathLabel.Text = d;

            app.subDirs = app.enumerateDataFolders(d);
            app.iFolder = 0;
            app.FolderStatusLabel.Text = sprintf('Folder: 0 / %d', numel(app.subDirs));
            app.clearFigure();
            app.TabGroup.SelectedTab = app.TabKTR;
            app.log(sprintf('Selected parent: %s (%d data folders)', d, numel(app.subDirs)));
        end

        function onStart(app,~,~)
            if isempty(app.subDirs)
                uialert(app.UIFigure,'Pick a parent folder that contains data folders.','Info'); 
                app.log('Start blocked: no data folders detected.');
                return;
            end
            mode = app.ModeDropDown.Value;
            if strcmp(mode,'Interactive')
                app.iFolder = 1;
                app.processCurrentFolder();
            else
                app.runAutoBatch();
            end
        end

        % ---- Quit button ----
        function onQuit(app,~,~)
            choice = uiconfirm(app.UIFigure, ...
                'Quit the app now? Unsaved changes for the current folder may be lost.', ...
                'Quit?', 'Options',{'Cancel','Quit'}, 'DefaultOption',2, 'CancelOption','Cancel');
            if ~strcmp(choice,'Quit'), return; end

            app.StopFlag = true;

            % Close progress dialog if open
            if ~isempty(app.ProgDlg)
                try, if isvalid(app.ProgDlg), close(app.ProgDlg); end, end
                app.ProgDlg = [];
            end

            if isvalid(app.UIFigure)
                delete(app.UIFigure);
            end
        end

        % ---- Interactive: KTR nav ----
        function onPrev(app,~,~)
            if isempty(app.dats_ktr), return; end
            app.j = max(1, app.j - 1);
            app.drawCurrentKTR();
        end

        function onDoneNext(app,~,~)
            if isempty(app.dats_ktr), return; end
            app.computeCurrentKTR();  % lock current
            if app.j < numel(app.dats_ktr)
                app.j = app.j + 1;
                app.drawCurrentKTR();
            else
                app.prepareAndShowHFS();
            end
        end

        function onSkipFile(app,~,~)
            if isempty(app.dats_ktr), return; end
            app.ktr_all(app.j)=NaN; app.force_all(app.j)=NaN; app.f0_all(app.j)=NaN; app.tmarks(app.j,:)=[NaN NaN NaN];
            if app.j < numel(app.dats_ktr), app.j = app.j+1; app.drawCurrentKTR(); else, app.prepareAndShowHFS(); end
        end

        function onSkipFolder(app,~,~)
            app.advanceFolder();
        end

        function onEditMark(app,k)
            if isempty(app.dats_ktr), return; end
            vals = [app.T1Field.Value, app.T2Field.Value, app.T3Field.Value];
            app.tmarks(app.j,k) = vals(k);
            if ~isempty(app.vLines{k}) && isvalid(app.vLines{k})
                yl = app.Ax.YLim; app.vLines{k}.Position = [vals(k) yl(1); vals(k) yl(2)];
            end
            app.computeCurrentKTR(false);
        end

        function onKeyNudge(app,evt)
            if isempty(app.vLines), return; end
            step = 0.001; % 1 ms
            switch evt.Key
                case 'leftarrow',  app.moveSelected(-step);
                case 'rightarrow', app.moveSelected(+step);
                case '1', app.selectLine(1);
                case '2', app.selectLine(2);
                case '3', app.selectLine(3);
            end
        end

        % ---- Interactive: HFS nav ----
        function onHFSPrev(app,~,~)
            if isempty(app.dats_hfs), return; end
            app.hfs_j = max(1, app.hfs_j - 1);
            app.drawCurrentHFS();
        end

        function onHFSNext(app,~,~)
            if isempty(app.dats_hfs), return; end
            app.hfs_j = min(numel(app.dats_hfs), app.hfs_j + 1);
            app.drawCurrentHFS();
        end

        function onHFSFinish(app,~,~)
            folderPath = app.subDirs(app.iFolder);
            app.saveCSVsForFolder(folderPath, app.folderName);
            app.advanceFolder();
        end

        function onTabChanged(app,~,~)
            if app.TabGroup.SelectedTab == app.TabKTR
                app.KCtrlGrid.Visible = 'on';
                app.HCtrlGrid.Visible = 'off';
            else
                if isempty(app.hfs_param) && ~isempty(app.dats_hfs)
                    app.computeHFSforFolder();
                end
                app.drawCurrentHFS();
                app.KCtrlGrid.Visible = 'off';
                app.HCtrlGrid.Visible = 'on';
            end
        end
    end

    %% ================== FLOW (INTERACTIVE) ==================
    methods (Access = private)
        function processCurrentFolder(app)
            p = app.subDirs(app.iFolder);
            parts = split(p, filesep); app.folderName = parts{end};
            app.FolderStatusLabel.Text = sprintf('Folder: %d / %d — %s', app.iFolder, numel(app.subDirs), app.folderName);

            [app.dats_ktr, app.dats_hfs] = app.readAndSplitFolder(char(p));
            app.log(sprintf('Loaded folder %s: %d KTR, %d HFS files.', app.folderName, numel(app.dats_ktr), numel(app.dats_hfs)));
            if isempty(app.dats_ktr) && isempty(app.dats_hfs)
                app.log('No files found here; advancing...');
                app.advanceFolder(); return;
            end

            N = numel(app.dats_ktr);
            app.cache     = cell(N,1);
            app.ktr_all   = nan(N,1);
            app.force_all = nan(N,1);
            app.f0_all    = nan(N,1);
            app.tmarks    = nan(N,3);
            app.j = 1;

            app.hfs_j = 1; app.hfs_param = []; app.hfs_f = {}; app.hfs_mag = {}; app.hfs_peakf = [];

            app.TabGroup.SelectedTab = app.TabKTR;
            try
            app.drawCurrentKTR();
            catch ME
              % Log details so we can see the root cause instead of a silent crash
            app.log(sprintf('drawCurrentKTR error: %s', ME.message));
            app.log(getReport(ME,'basic','hyperlinks','off'));
            % Fail-safe: go compute/preview HFS so the app remains usable
            try
            app.computeHFSforFolder();
            app.TabGroup.SelectedTab = app.TabHFS;
            app.hfs_j = 1;
            app.drawCurrentHFS();
            catch ME2
            app.log(sprintf('Fallback to HFS also failed: %s', ME2.message));
            end
           end

        end

        function prepareAndShowHFS(app)
            app.computeHFSforFolder();
            app.TabGroup.SelectedTab = app.TabHFS;
            app.hfs_j = 1;
            app.drawCurrentHFS();
        end

        function advanceFolder(app)
            if app.iFolder < numel(app.subDirs)
                app.iFolder = app.iFolder + 1;
                app.clearFigure();
                app.processCurrentFolder();
            else
                app.clearFigure();
                app.FolderStatusLabel.Text = sprintf('Done! Processed %d folders.', numel(app.subDirs));
                if isvalid(app.UIFigure)
                    uialert(app.UIFigure,'Batch processing complete.','Done','Icon','success');
                end
                app.log('All folders processed (interactive).');
            end
        end
    end

    %% ================== AUTO MODE ==================
    methods (Access = private)
        function runAutoBatch(app)
            if isempty(app.subDirs)
                uialert(app.UIFigure,'No data folders found under the selected parent.','Nothing to do');
                app.log('Auto: no folders to process.'); return;
            end

            % Lock UI + busy cursor
            app.KCtrlGrid.Visible = 'off';
            app.HCtrlGrid.Visible = 'off';
            app.TabGroup.Visible  = 'off';     % (TabGroup has no Enable in some releases)
            app.StartButton.Enable = 'off';
            app.SelectParentButton.Enable = 'off';
            app.StopFlag = false;

            oldPtr = app.UIFigure.Pointer;
            app.UIFigure.Pointer = 'watch';
            drawnow;

            Nfolders = numel(app.subDirs);
            app.ProgDlg = uiprogressdlg(app.UIFigure,'Title','Auto mode','Message','Starting…','Indeterminate','off');

            for i = 1:Nfolders
                if app.StopFlag || ~isvalid(app.UIFigure), break; end

                app.iFolder = i;
                folderPath  = app.subDirs(i);
                parts = split(folderPath, filesep); base = parts{end};

                app.ProgDlg.Value   = (i-1)/max(Nfolders,1);
                app.ProgDlg.Message = sprintf('Folder %d / %d — %s', i, Nfolders, base);
                drawnow;

                try
                    [dats_ktr, dats_hfs] = app.readAndSplitFolder(char(folderPath));
                    app.log(sprintf('[AUTO] %s: %d KTR, %d HFS', base, numel(dats_ktr), numel(dats_hfs)));

                    % KTR auto
                    [ktr_all, force_all, f0_all, tmarks] = app.computeKTRAuto(dats_ktr);

                    % HFS auto
                    app.dats_hfs = dats_hfs;
                    app.computeHFSforFolder();

                    % Save per folder
                    app.folderName = base;
                    app.ktr_all    = ktr_all;
                    app.force_all  = force_all;
                    app.f0_all     = f0_all;
                    app.tmarks     = tmarks;
                    app.saveCSVsForFolder(char(folderPath), base);
                    app.log(sprintf('[AUTO] Saved CSVs in %s', folderPath));
                catch ME
                    app.log(sprintf('[AUTO][ERROR] %s: %s', base, ME.message));
                end
            end

            % Close dialog & restore UI safely
            if ~isempty(app.ProgDlg)
                try, if isvalid(app.ProgDlg), close(app.ProgDlg); end, end
                app.ProgDlg = [];
            end
            if isvalid(app.UIFigure)
                app.UIFigure.Pointer = oldPtr;
                app.TabGroup.Visible = 'on';
                app.StartButton.Enable = 'on';
                app.SelectParentButton.Enable = 'on';
                if ~app.StopFlag
                    uialert(app.UIFigure,'Auto run complete. CSVs saved in each folder.','Done','Icon','success');
                    app.log('All folders processed (auto).');
                end
            end
        end

        function [ktr_all, force_all, f0_all, tmarks] = computeKTRAuto(app, dats_ktr)
            N = numel(dats_ktr);
            ktr_all = nan(N,1); force_all = nan(N,1); f0_all = nan(N,1); tmarks = nan(N,3);
            for j = 1:N
                try
                    [t, f] = app.parseKTR(dats_ktr{j});
                    if numel(t) < 5 || numel(f) ~= numel(t)
                        app.log(sprintf('[AUTO] KTR #%d skipped: insufficient data', j));
                        continue;
                    end

                    % default marks = nearest to guesses (clamped)
                    tj = zeros(1,3);
                    for k=1:3
                        g = min(max(app.guessT(k), t(1)), t(end));
                        tj(k) = t(app.nearestIdx(t, g));
                    end
                    tmarks(j,:) = tj;

                    [ok, ktr, force, f0] = app.safeComputeKTRFromMarks(t, f, tj);
                    if ~ok
                        app.log(sprintf('[AUTO] KTR #%d fit failed.', j));
                        continue;
                    end
                    ktr_all(j)   = ktr;
                    force_all(j) = force;
                    f0_all(j)    = f0;
                catch ME
                    app.log(sprintf('[AUTO] KTR #%d error: %s', j, ME.message));
                end
            end
        end
    end

    %% ================== KTR (INTERACTIVE DRAW/COMPUTE) ==================
    methods (Access = private)
        function drawCurrentKTR(app)
            N = numel(app.dats_ktr);
            app.RecordIdxLabel.Text = sprintf('Record: %d / %d', app.j, max(N,0));
            cla(app.Ax);
            if ~isempty(app.fitLine) && isvalid(app.fitLine), delete(app.fitLine); app.fitLine=[]; end

            if N == 0
                text(app.Ax,0.5,0.5,'No .1 (KTR) files','Units','normalized','HorizontalAlignment','center');
                app.T1Field.Enable='off'; app.T2Field.Enable='off'; app.T3Field.Enable='off';
                app.T1Field.Value=0; app.T2Field.Value=0; app.T3Field.Value=0;
                app.ForceValLabel.Text='—'; app.KtrValLabel.Text='—'; app.F0ValLabel.Text='—';
                return;
            end

            % cache parse
            try
                if isempty(app.cache{app.j})
                    [t,f] = app.parseKTR(app.dats_ktr{app.j});
                    app.cache{app.j} = struct('t',t,'f',f);
                else
                    t = app.cache{app.j}.t; f = app.cache{app.j}.f;
                end
            catch ME
                app.log(sprintf('Parse error (KTR #%d): %s', app.j, ME.message));
                app.onSkipFile(); return;
            end

            if numel(t) < 5 || ~isvector(t)
                app.log(sprintf('Insufficient data (KTR #%d), skipping.', app.j));
                app.onSkipFile(); return;
            end

            plot(app.Ax, t, f, '.', 'MarkerSize', 6); hold(app.Ax,'on');

            % seed marks near guesses
            for k = 1:3
                if isnan(app.tmarks(app.j,k))
                    g = min(max(app.guessT(k), t(1)), t(end));
                    app.tmarks(app.j,k) = t(app.nearestIdx(t, g));
                end
            end
            app.T1Field.Value = app.tmarks(app.j,1);
            app.T2Field.Value = app.tmarks(app.j,2);
            app.T3Field.Value = app.tmarks(app.j,3);
            app.T1Field.Enable='on'; app.T2Field.Enable='on'; app.T3Field.Enable='on';

        % --- draggables (recreate 3 vertical lines) ---
            app.deleteLines();

            % ensure cell exists and has 3 slots
            if isempty(app.vLines) || numel(app.vLines) < 3
            app.vLines = cell(1,3);
            end

            yl = app.Ax.YLim;
            for k = 1:3
            xk = app.tmarks(app.j,k);
            % Defensive clamp in case guesses landed slightly outside axis limits
            if xk < app.Ax.XLim(1), xk = app.Ax.XLim(1); end
            if xk > app.Ax.XLim(2), xk = app.Ax.XLim(2); end

            app.vLines{k} = drawline(app.Ax, ...
            'Position', [xk yl(1); xk yl(2)]);
            app.setupLine(app.vLines{k}, k);
            end


            app.computeCurrentKTR(true);
        end

        function computeCurrentKTR(app, drawFit)
            if nargin<2, drawFit=true; end
            t = app.cache{app.j}.t; f = app.cache{app.j}.f;

            % keep vertical & sync
            for k=1:3
                if ~isempty(app.vLines{k}) && isvalid(app.vLines{k})
                    yl = app.Ax.YLim;
                    app.vLines{k}.Position = [app.vLines{k}.Position(1,1) yl(1); app.vLines{k}.Position(2,1) yl(2)];
                    app.tmarks(app.j,k) = app.vLines{k}.Position(1,1);
                end
            end
            app.T1Field.Value = app.tmarks(app.j,1);
            app.T2Field.Value = app.tmarks(app.j,2);
            app.T3Field.Value = app.tmarks(app.j,3);

            [ok, ktr, force_jj, f0, yfit, tfit] = app.safeComputeKTRFromMarks(t, f, app.tmarks(app.j,:));
            if ~ok
                app.KtrValLabel.Text='NaN'; app.ForceValLabel.Text='NaN'; app.F0ValLabel.Text='NaN';
                app.log(sprintf('Fit failed at record %d (folder %s). Adjust marks.', app.j, app.folderName));
                return;
            end

            app.ktr_all(app.j)   = ktr;
            app.force_all(app.j) = force_jj;
            app.f0_all(app.j)    = f0;
            app.KtrValLabel.Text   = sprintf('%.4g', ktr);
            app.ForceValLabel.Text = sprintf('%.4g', force_jj);
            app.F0ValLabel.Text    = sprintf('%.4g', f0);

            if drawFit
                if ~isempty(app.fitLine) && isvalid(app.fitLine), delete(app.fitLine); end
                app.fitLine = plot(app.Ax, tfit, yfit + f0, 'LineWidth', 2);
            end
        end

        function [ok, ktr, force_jj, f0, yfit, tfit] = safeComputeKTRFromMarks(app, t, f, tj)
            ok=false; ktr=NaN; force_jj=NaN; f0=NaN; yfit=[]; tfit=[];
            [~,i1] = min(abs(t - tj(1)));
            [~,i2] = min(abs(t - tj(2)));
            [~,i3] = min(abs(t - tj(3)));
            if i2 < i1, tmp=i1; i1=i2; i2=tmp; end
            if any([i1,i2,i3] < 1) || any([i1,i2,i3] > numel(t)) || i2 <= i1 || i3 >= numel(t)
                return;
            end
            [~,i4] = min(abs(t - app.t4));

            f0 = mean(f(i1:i2));
            tktr = t(i3:end) - t(i3);
            fktr = f(i3:end) - f0;

            if ~isvector(tktr) || numel(tktr) < 5, return; end

            Ft = @(p,tt) p(1).*(1 - exp(-p(2).*tt)) + p(3);
            x0 = [max(fktr), 1, min(fktr)];
            try
                my_fit = lsqcurvefit(Ft, x0, tktr, fktr, [], [], optimoptions('lsqcurvefit','Display','off'));
            catch
                try
                    obj = @(p) norm(Ft(p, tktr) - fktr);
                    my_fit = fminsearch(obj, x0, optimset('Display','off'));
                catch
                    return;
                end
            end
            yfit = Ft(my_fit, tktr);
            tfit = t(i3:end);

            i4r = max(1, i4 - i3 + 1);
            force_jj = mean(fktr(i4r:end));
            ktr = my_fit(2);
            ok = true;
        end
    end

    %% ================== HFS (FFT) ==================
    methods (Access = private)
        function computeHFSforFolder(app)
            M = numel(app.dats_hfs);
            app.hfs_param = nan(M,1);
            app.hfs_f     = cell(M,1);
            app.hfs_mag   = cell(M,1);
            app.hfs_peakf = nan(M,1);

            for kk = 1:M
                try
                    [scan_rate, CSA, cal_factor, T, ML, Fv] = app.parseHFS(app.dats_hfs{kk}); %#ok<ASGLU>
                    if numel(T) < 5
                        app.log(sprintf('HFS #%d skipped: insufficient data.', kk));
                        continue;
                    end

                    i1 = app.nearestIdx(T, 0.5002);
                    i2 = app.nearestIdx(T, 0.5409);
                    if i2 <= i1, i2 = min(numel(T), i1+round(0.04*length(T))); end

                    y = ML(i1:i2) .* 7.7;
                    Y = fft(y); magY = abs(Y);
                    magDen = max(magY);
                    try
                        pksY = findpeaks(magY,'SortStr','descend','NPeaks',3);
                        if ~isempty(pksY), magDen = pksY(1); end
                    catch, end

                    z = Fv(i1:i2) ./ (CSA*cal_factor);
                    Z = fft(z); magZ = abs(Z);

                    N  = numel(z);
                    f  = (0:N-1)*(scan_rate/N);

                    pkMag = max(magZ); pkIdx = find(magZ==pkMag,1);
                    try
                        [pksZ, locsZ] = findpeaks(magZ,'SortStr','descend','NPeaks',3);
                        if ~isempty(pksZ), pkMag=pksZ(1); pkIdx=locsZ(1); end
                    catch, end

                    app.hfs_param(kk) = pkMag / max(eps,magDen);
                    app.hfs_f{kk}     = f;
                    app.hfs_mag{kk}   = magZ;
                    app.hfs_peakf(kk) = f(min(max(pkIdx,1),numel(f)));
                catch ME
                    app.log(sprintf('HFS #%d error: %s', kk, ME.message));
                end
            end
        end

        function drawCurrentHFS(app)
            cla(app.AxFFT);
            M = numel(app.dats_hfs);
            app.HFSIdxLabel.Text = sprintf('HFS: %d / %d', min(app.hfs_j,M), max(M,0));

            if M == 0
                text(app.AxFFT,0.5,0.5,'No .2 (HFS) files','Units','normalized','HorizontalAlignment','center');
                app.HFSParamValLabel.Text='—';
                return;
            end

            f   = app.hfs_f{app.hfs_j};
            mag = app.hfs_mag{app.hfs_j};
            if isempty(f) || isempty(mag)
                text(app.AxFFT,0.5,0.5,'(empty FFT)','Units','normalized','HorizontalAlignment','center');
                app.HFSParamValLabel.Text='NaN'; return;
            end

            plot(app.AxFFT, f, mag, 'LineWidth', 1.2); grid(app.AxFFT,'on');
            xlabel(app.AxFFT,'Frequency (Hz)'); ylabel(app.AxFFT,'|Z(f)|');
            title(app.AxFFT, sprintf('Folder %s — HFS #%d', app.folderName, app.hfs_j));

            pf = app.hfs_peakf(app.hfs_j);
            if ~isnan(pf)
                yl = app.AxFFT.YLim;
                line(app.AxFFT, [pf pf], yl, 'LineStyle','--','LineWidth',1);
                text(app.AxFFT, pf, yl(2), sprintf('  peak @ %.3g Hz', pf), 'VerticalAlignment','top');
            end

            val = app.hfs_param(app.hfs_j);
            if isnan(val), app.HFSParamValLabel.Text='NaN';
            else, app.HFSParamValLabel.Text=sprintf('%.4g', val);
            end
        end
    end

    %% ================== SAVE / IO / HELPERS ==================
    methods (Access = private)
        function saveCSVsForFolder(app, folderPath, base)
            if nargin < 2 || isempty(folderPath)
                folderPath = app.subDirs(app.iFolder);
            end
            if nargin < 3 || isempty(base)
                base = app.folderName;
            end
            folderPath = char(folderPath);

            if ~isempty(app.ktr_all) && ~all(isnan(app.ktr_all))
                Tktr = table( (1:numel(app.ktr_all))', ...
                              app.tmarks(:,1), app.tmarks(:,2), app.tmarks(:,3), ...
                              app.f0_all, app.force_all, app.ktr_all, ...
                              'VariableNames',{'index','t1','t2','t3','f0','force_mNmm2','ktr_1_per_s'});
                fn = fullfile(folderPath, sprintf('%s_ktr.csv', base));
                writetable(Tktr, fn);
                app.log(['Saved ', fn]);
            end
            if ~isempty(app.hfs_param) && ~all(isnan(app.hfs_param))
                fn = fullfile(folderPath, sprintf('%s_hfs.csv', base));
                writematrix(app.hfs_param, fn);
                app.log(['Saved ', fn]);
            end
        end

        function [dats_ktr,dats_hfs] = readAndSplitFolder(app, folderPath) %#ok<INUSD>
            L = dir(folderPath); L = L(~[L.isdir]);
            names = {L.name};
            if isempty(names), dats_ktr={}; dats_hfs={}; return; end

            toks = regexp(names,'\d+\.\d+','match');
            keep = ~cellfun(@isempty, toks);
            L = L(keep); names = names(keep); toks = toks(keep);
            if isempty(L), dats_ktr={}; dats_hfs={}; return; end

            nums = cellfun(@(x) str2double(x{1}), toks);
            [~, ord] = sort(nums);
            L = L(ord); names = names(ord);

            dats_all = cell(numel(L),1);
            for ii = 1:numel(L)
                fn = fullfile(L(ii).folder, L(ii).name);
                try
                    fid = fopen(fn);
                    dat = textscan(fid,'%[^\n]','Whitespace','');
                    fclose(fid);
                    dats_all{ii,1} = dat{1,1};
                catch
                    if fid>0, fclose(fid); end
                    app.log(['Read error: ', fn]);
                    dats_all{ii,1} = {};
                end
            end

            is_dot1 = endsWith(names, '.1');
            is_dot2 = endsWith(names, '.2');
            dats_ktr = dats_all(is_dot1);
            dats_hfs = dats_all(is_dot2);
        end

        function [t,f] = parseKTR(~, datjj)
            x = find(contains(datjj, "Time (s)") & contains(datjj, "ML (V)") & contains(datjj, "Force (V)"), 1);
            assert(~isempty(x), 'KTR header not found');
            raw = datjj(x+1:end,1);
            rows = cellfun(@(line) strsplit(line, '\t'), raw, 'UniformOutput', false);
            rows = cellfun(@(row) str2double(row), rows, 'UniformOutput', false);
            A = vertcat(rows{:});

            midx = find(contains(datjj, 'Fiber diameter'), 1);
            assert(~isempty(midx), 'Fiber diameter missing');
            tokens = regexp(datjj{midx}, '[\t:]\s*', 'split');
            D  = str2double(tokens{end});
            D2 = 0.5*D;
            CSA = (((D+D2)/2)*(1e-3)/2)^2*pi;

            idx = find(contains(datjj, 'Factor to convert data to physical units:'), 1);
            assert(~isempty(idx), 'Cal factor missing');
            tokens = strsplit(datjj{idx}, '\t');
            cal_factor = str2double(tokens{3});

            t = A(:,1);
            f = A(:,3) / max(eps, (CSA*cal_factor));
        end

        function [scan_rate, CSA, cal_factor, T, ML, Fv] = parseHFS(~, datkk)
            x = find(contains(datkk, "Time (s)") & contains(datkk, "ML (V)") & contains(datkk, "Force (V)"), 1);
            assert(~isempty(x), 'HFS header not found');
            raw = datkk(x+1:end,1);
            rows = cellfun(@(line) strsplit(line, '\t'), raw, 'UniformOutput', false);
            rows = cellfun(@(row) str2double(row), rows, 'UniformOutput', false);
            A = vertcat(rows{:});     % [Time, ML, Force] (V)
            T = A(:,1); ML = A(:,2); Fv = A(:,3);

            midx = find(contains(datkk, 'Fiber diameter'), 1);
            assert(~isempty(midx), 'Fiber diameter missing');
            tokens = regexp(datkk{midx}, '[\t:]\s*', 'split');
            D  = str2double(tokens{end});
            D2 = 0.5*D;
            CSA = (((D+D2)/2)*(1e-3)/2)^2*pi;

            match_idfreq = find(contains(datkk, 'scan rate (scans/s):','IgnoreCase',true),1);
            assert(~isempty(match_idfreq), 'Scan rate missing');
            tokens_freq = split(datkk{match_idfreq}, ':');
            scan_rate = str2double(strtrim(tokens_freq{2}));

            idy = find(contains(datkk, 'Factor to convert data to physical units:'), 1);
            assert(~isempty(idy), 'Cal factor missing');
            tokens = strsplit(datkk{idy}, '\t');
            cal_factor = str2double(tokens{3});
        end

        function i = nearestIdx(~, vec, val)
            [~,i] = min(abs(vec - val));
        end

        function setupLine(app, hline, k)
            yl = app.Ax.YLim;
            hline.Position = [hline.Position(1,1) yl(1); hline.Position(2,1) yl(2)];
            hline.InteractionsAllowed = 'translate';
            if k==1, hline.Color=[0 0.6 0];
            elseif k==2, hline.Color=[0.8 0.4 0];
            else, hline.Color=[0 0.45 0.74]; end
            hline.LineWidth = 1.5;
            addlistener(hline,'MovingROI', @(src,evt) app.onLineMove(k,src)); %#ok<NASGU>
            addlistener(hline,'ROIMoved',  @(src,evt) app.onLineMove(k,src)); %#ok<NASGU>
        end

        function onLineMove(app, k, hline)
            t_now = hline.Position(1,1);
            app.tmarks(app.j,k) = t_now;
            if k==1, app.T1Field.Value=t_now; elseif k==2, app.T2Field.Value=t_now; else, app.T3Field.Value=t_now; end
            app.computeCurrentKTR(false);
        end

        function deleteLines(app)
            if isempty(app.vLines), return; end
            for k=1:numel(app.vLines)
                if ~isempty(app.vLines{k}) && isvalid(app.vLines{k}), delete(app.vLines{k}); end
                app.vLines{k} = [];
            end
        end

        function selectLine(app,k)
            for m=1:3
                if ~isempty(app.vLines{m}) && isvalid(app.vLines{m}), app.vLines{m}.LineWidth = 1.5; end
            end
            if ~isempty(app.vLines{k}) && isvalid(app.vLines{k}), app.vLines{k}.LineWidth = 3; end
        end

        function moveSelected(app,dx)
            widths = zeros(1,3);
            for m=1:3
                if ~isempty(app.vLines{m}) && isvalid(app.vLines{m}), widths(m)=app.vLines{m}.LineWidth; end
            end
            [~,k] = max(widths);
            if k<1 || k>3 || isempty(app.vLines{k}) || ~isvalid(app.vLines{k}), return; end
            x0 = app.vLines{k}.Position(1,1);
            yl = app.Ax.YLim;
            app.vLines{k}.Position = [x0+dx yl(1); x0+dx yl(2)];
            app.onLineMove(k, app.vLines{k});
        end

        function clearFigure(app)
            if ~isempty(app.Ax), cla(app.Ax); end
            if ~isempty(app.AxFFT), cla(app.AxFFT); end
            app.deleteLines();
            if ~isempty(app.fitLine) && isvalid(app.fitLine), delete(app.fitLine); app.fitLine=[]; end
            app.T1Field.Enable='off'; app.T2Field.Enable='off'; app.T3Field.Enable='off';
            app.T1Field.Value=0; app.T2Field.Value=0; app.T3Field.Value=0;
            app.ForceValLabel.Text='—'; app.KtrValLabel.Text='—'; app.F0ValLabel.Text='—';
            app.RecordIdxLabel.Text='Record: — / —';
            if ~isempty(app.HFSIdxLabel), app.HFSIdxLabel.Text='HFS: — / —'; app.HFSParamValLabel.Text='—'; end
        end

        function subs = enumerateDataFolders(app, parent)
            subs = strings(0,1);
            S = dir(parent);
            for k = 1:numel(S)
                if S(k).isdir && ~ismember(S(k).name,{'.','..'})
                    p = fullfile(parent, S(k).name);
                    if app.folderHasData(p)
                        subs(end+1,1) = string(p); %#ok<AGROW>
                    else
                        subs = [subs; app.enumerateDataFolders(p)]; %#ok<AGROW>
                    end
                end
            end
        end

        function tf = folderHasData(~, p)
            L = dir(p); L = L(~[L.isdir]);
            names = {L.name};
            if isempty(names), tf=false; return; end
            hasNum = any(~cellfun('isempty', regexp(names,'\d+\.\d+','once')));
            hasDot = any(endsWith(names, {'.1','.2'}));
            tf = hasNum || hasDot;
        end

        function log(app, msg)
            try
                app.StatusArea.Value = [app.StatusArea.Value; {msg}];
                drawnow limitrate;
            catch
                fprintf('%s\n',msg);
            end
        end
    end
end
