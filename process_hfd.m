function varargout = process_hfd( varargin )
% PROCESS_HFD: Computes the HFD of all the trials, and average them.

% @=============================================================================
% This function is part of the Brainstorm software:
% https://neuroimage.usc.edu/brainstorm
% 
% Copyright (c) University of Southern California & McGill University
% This software is distributed under the terms of the GNU General Public License
% as published by the Free Software Foundation. Further details on the GPLv3
% license can be found at http://www.gnu.org/copyleft/gpl.html.
% 
% FOR RESEARCH PURPOSES ONLY. THE SOFTWARE IS PROVIDED "AS IS," AND THE
% UNIVERSITY OF SOUTHERN CALIFORNIA AND ITS COLLABORATORS DO NOT MAKE ANY
% WARRANTY, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO WARRANTIES OF
% MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE, NOR DO THEY ASSUME ANY
% LIABILITY OR RESPONSIBILITY FOR THE USE OF THIS SOFTWARE.

%Author: Patricia Ruperez

% =============================================================================@


eval(macro_method);
end


%% ===== GET DESCRIPTION =====
function sProcess = GetDescription() %#ok<DEFNU>
    % Description the process
    sProcess.Comment     = 'Higuchi''s Fractal Dimension';
    sProcess.Category    = 'Custom';
    sProcess.SubGroup    = 'Frequency';
    sProcess.Index       = 480;
    %sProcess.Description = 'https://neuroimage.usc.edu/brainstorm/Tutorials/ArtifactsFilter#Evaluation_of_the_noise_level';
    % Definition of the input accepted by this process
    sProcess.InputTypes  = {'data', 'raw', 'results'};
    sProcess.OutputTypes = {'data', 'data', 'results'};
    sProcess.nInputs     = 1;
    sProcess.nMinFiles   = 1;
    % Options: Time window
    sProcess.options.timewindow.Comment = 'Time window:';
    sProcess.options.timewindow.Type    = 'timewindow';
    sProcess.options.timewindow.Value   = [];
    sProcess.options.timewindow.InputTypes = {'raw', 'data', 'results'};
    % Options: Sensor types
    sProcess.options.sensortypes.Comment = 'Sensor types or names (empty=all): ';
    sProcess.options.sensortypes.Type    = 'text';
    sProcess.options.sensortypes.Value   = 'MEG, EEG';
    sProcess.options.sensortypes.InputTypes = {'raw','data'};
    % Options: Select specific electrodes
    sProcess.options.electrodes.Comment = 'Electrode names in case raw or data input (not sources) (comma-separated, leave blank for all):';
    sProcess.options.electrodes.Type    = 'text';
    sProcess.options.electrodes.Value   = '';
    % Options: Kmax value
    sProcess.options.kmax.Comment = 'Maximum k value (HFD)';
    sProcess.options.kmax.Type    = 'value';
    sProcess.options.kmax.Value   = {30, '', 0}; % Default value is 30
    % Options: HFD calculation method
    sProcess.options.calcMethod.Comment = 'HFD calculation method:';
    sProcess.options.calcMethod.Type    = 'combobox';
    sProcess.options.calcMethod.Value   = {1, {'HFD of whole signal', 'HFD at sensor/source level (averaged)', 'HFD at sensor/source level (individual values)'}};

end


%% ===== FORMAT COMMENT =====
function Comment = FormatComment(sProcess) %#ok<DEFNU>
    Comment = sProcess.Comment;
end


%% ===== RUN =====
function OutputFiles = Run(sProcess, sInputs) %#ok<DEFNU>
    %Initialize output files list
    OutputFiles = {};

    %Iterate over each input file
    for iInput = 1:numel(sInputs)
        %Determine input type
        inputType = sInputs(iInput).FileType;

        % ***Get process options***
        calcMethod = sProcess.options.calcMethod.Value{1}; % Selected method
        selectedElectrodes = strsplit(strtrim(sProcess.options.electrodes.Value), ','); % Selected electrodes
        k_max = sProcess.options.kmax.Value{1}; % Maximum k value for HFD
        timeWindow = sProcess.options.timewindow.Value; %[start_time, end_time]
        timeWindow = timeWindow{1};

        % ***Get input data***
        switch inputType
            case 'data'
                DataMat = in_bst_data(sInputs(iInput).FileName); % Load the input data
                EEG = DataMat.F; % EEG data matrix [channels x time]
                timeVector = DataMat.Time; % [1 x Ntime] array of time points
                if ~isempty(timeWindow) && (~isequal(timeWindow(1), min(timeVector)) || ~isequal(timeWindow(2), max(timeVector))) %If time window is specified
                    timeVector = DataMat.Time; % [1 x Ntime] array of time points
                    timeIndices = find(timeVector >= timeWindow(1) & timeVector <= timeWindow(2));
                    if isempty(timeIndices)
                        error('Specified time window is outside the range of the source file.')
                    end
                    EEG = EEG(:, timeIndices);
                end
                ChannelMat = in_bst_channel(sInputs(iInput).ChannelFile); % Load channel file
                ChannelNames = {ChannelMat.Channel.Name}; % Extract channel names
            case 'raw'
                % [sMat, F, TimeVector] = in_bst_raw(sInputs(iInput).FileName, [], [], []);
                % EEG = F;
                [sFile, ChannelMat, errMsg] = in_fopen(sInputs(iInput).FileName, 'BST-DATA');
                %Check for errors
                if ~isempty(errMsg)
                    error(['Error opening file: ', errMsg']);
                end
                %Parameters for reading
                iEpoch = 1; 
                iChannels = [];
                timeRange = sFile.prop.times; %Total time range [start_time, end_time]
                if ~isempty(timeWindow) && ~isequal(timeWindow, timeRange)
                    sfreq = sFile.prop.sfreq; %Sampling frequency
                    SampleBounds = round(timeWindow * sfreq) + 1; %Convert to start_sample, end_sample]%NOte that time 0 occupies position 1
                    %Ensure SampleBounds are within valid range
                    if (SampleBounds(1) < 1) || (SampleBounds(2) > (ceil(diff(timeRange) * sfreq) + 1))
                        error('Specified time window is outside the range of the source file.')
                    end
                else
                    SampleBounds = [];
                end
                [EEG, time] = in_fread(sFile.header.F, [], iEpoch, SampleBounds, iChannels);
                ChannelNames = {ChannelMat.Channel.Name}; % Extract channel names
            case 'results'
                SourceMat = in_bst_results(sInputs(iInput).FileName, 0);
                isRaw = contains(SourceMat.DataFile, '@raw');
                switch isRaw 
                    case 0
                        timeVector = SourceMat.Time; %[1 x Ntime] array of points
                        %Select window time data, if specified
                        if ~isempty(timeWindow) && (~isequal(timeWindow(1), min(timeVector)) || ~isequal(timeWindow(2), max(timeVector)))
                            timeIndices = find(timeVector >= timeWindow(1) & timeVector <= timeWindow(2));
                            SampleBounds = [min(timeIndices), max(timeIndices)];
                            if isempty(timeIndices)
                                error('Specified time window is outside the range of the source file.')
                            end
                        else
                            SampleBounds = [];
                        end
                        [sFile, ChannelMat, errMsg] = in_fopen(SourceMat.DataFile, 'BST-DATA');
                        iEpoch = 1;
                        iChannels = [];
                        [EEG] = in_fread(sFile, [], iEpoch, SampleBounds, iChannels);
                        EEG_sources = SourceMat.ImagingKernel*EEG;
                    case 1
                        [sFile, ChannelMat, errMsg] = in_fopen(SourceMat.DataFile, 'BST-DATA');
                        %Check for errors
                        if ~isempty(errMsg)
                            error(['Error opening file: ', errMsg']);
                        end
                        %Parameters for reading
                        iEpoch = 1; 
                        timeRange = sFile.prop.times; %Total time range [start_time, end_time]
                        if ~isempty(timeWindow) && ~isequal(timeWindow, timeRange)
                            sfreq = sFile.prop.sfreq; %Sampling frequency
                            SampleBounds = round(timeWindow * sfreq) + 1; %Convert to start_sample, end_sample]%NOte that time 0 occupies position 1
                            %Ensure SampleBounds are within valid range
                            if (SampleBounds(1) < 1) || (SampleBounds(2) > (ceil(diff(timeRange) * sfreq) + 1))
                                error('Specified time window is outside the range of the source file.')
                            end
                        else
                            SampleBounds = [];
                        end
                        iChannels = [];
                        [EEG] = in_fread(sFile.header.F, [], iEpoch, SampleBounds, iChannels);
                        EEG_sources = SourceMat.ImagingKernel*EEG; 
                    end
                SourcePoints = SourceMat.GridLoc; % Coordenadas 3D de las fuentes
                if ~isempty(SourcePoints)
                    SourceNames = arrayfun(@(x) sprintf('Source_%d', x), 1:size(SourcePoints, 1), 'UniformOutput', false);
                else
                    SourceNames = {};
                end

        end
        
        %Process data obtained

        switch inputType
            case {'data', 'raw'}

                %***Check selected electrodes, if they are specified, and match the
                %channel number
                if ~isempty(selectedElectrodes{1}) % If electrodes specified
                    selectedIdx = find(ismember(ChannelNames, selectedElectrodes));
                    if isempty(selectedIdx)
                        bst_report('Error', sProcess, sInputs, 'No matching electrodes found.');
                        OutputFiles = {};
                        return;
                    end
                    EEG = EEG(selectedIdx, :); % Filter EEG to selected electrodes
                    ChannelNames = ChannelNames(selectedIdx);
                end
            
                %***CALCULATE HFD***
                
                switch calcMethod
                    case 1 %HFD of whole signal
                        %Combine data from all selected sensors
                        combinedSignal = reshape(EEG', 1, []); % Merge all sensor data into one signal
                        HFD = compute_hfd(combinedSignal, k_max);
                        Comment   = ['HFD of whole signal, kmax=' num2str(k_max)];
            
                    case 2 %Mean HFD at sensor level
                        %Create matrix to save HFD values
                        % num_electrodes = length(ChannelNames);
                        % HFD_values = zeros (1, num_electrodes); %Vector for saving HFD values
                        % for i = 1 : num_electrodes
                        %     HFD_values(i) = compute_hfd(EEG(i, :), k_max);
                        % end
                        HFD_values = arrayfun(@(ChannelNames) compute_hfd(EEG(ChannelNames, :), k_max), 1:size(EEG, 1));
                        HFD = mean(HFD_values);
                        Comment   = ['HFD sensor averaged, kmax=' num2str(k_max)];
            
                    case 3  %HFD at sensor level (one value for each sensor)
                        %Create matrix to save HFD values
                        % num_electrodes = length(ChannelNames);
                        % HFD = zeros (1, num_electrodes); %Vector for saving HFD values
                        % for i = 1 : num_electrodes
                        %     eeg_signal = EEG(i, :); %Extract the signal for each electrode
                        %     %Compute HFD values for the electrode
                        %     HFD(i) = compute_hfd(eeg_signal, k_max);
                        % end
                        % HFD = array2table(HFD, 'VariableNames', ChannelNames);
                        HFD = arrayfun(@(ChannelNames) compute_hfd(EEG(ChannelNames, :), k_max), 1:size(EEG, 1));
                        Comment   = ['HFD at sensor level, kmax=' num2str(k_max)];
                end

                %Create a structure for saving
                HFDStruct = db_template('data');
                HFDStruct.Comment = Comment;
                HFDStruct.F = HFD'; % Each row corresponds to a channel
                HFDStruct.Time = 0;   %Static data, so just one time point
                HFDStruct.ChannelFlag = ones(size(HFD)); %Good sensors (1)
                %HFDStruct.ChannelNames   = {ChannelNames}; % List of channel names
                HFDStruct.DataFile  = sInputs(iInput).FileName; % Original file reference
                HFDStruct.History   = {datetime("now"), 'Computed HFD'}; % Log of processing steps
                HFDStruct.CreatedBy = 'process_hdf';
        
                % Save and register the file in the database
                [sStudy, iStudy, Comment, uniqueDataFile] = bst_process('GetOutputStudy', sProcess, sInputs(iInput));
                OutputFile = bst_process('GetNewFilename', bst_fileparts(sStudy.FileName), 'data_HFD');
                bst_save(OutputFile, HFDStruct, 'v6', 0);
                db_add_data(sInputs(iInput).iStudy, OutputFile, HFDStruct);
                OutputFiles{end+1} = OutputFile; %Append to output list

            case 'results'

                [N_sources, N_timepoints] = size(EEG_sources);
                EEG = EEG_sources;

                %Calculation of HFD depending on Calculation method chosen
                switch calcMethod

                    case 1 %HFD of the whole signal
                        combinedSignal = reshape(EGG', 1, []); %Merge all sensor data into one array
                        HFD = compute_hfd(combinedSignal, k_max);
                        Comment = ['HFD of whole signal(sources), kmax=' num2str(k_max)];

                    case 2 %Mean HFD at source level
                        %Calculate hFD for each source and calculate the
                        %mean
                        HFD_values = arrayfun(@(iSource) compute_hfd(EEG(iSource, :), k_max), 1:N_sources);
                        HFD = mean(HFD_values);
                        Comment = ['HFD source-averaged, kmax=' num2str(k_max)];

                    case 3 %Individual HFD value for each source
                        HFD = arrayfun(@(iSource) compute_hfd(EEG(iSource, :), k_max), 1:N_sources);
                        Comment = ['HFD per source, kmax=' num2str(k_max)];
                end
                %Create output structure
                HFDStruct = db_template('results');
                HFDStruct.Comment = Comment;
                HFDStruct.ImagingKernel = [];
                HFDStruct.ImageGridAmp = HFD';
                %HFDStruct.ImageGridAmp = HFD'; %Save HFD values
                HFDStruct.Time = 0; %Static data in time
                HFDStruct.nComponents = SourceMat.nComponents;
                HFDStruct.DataFile = SourceMat.DataFile;
                HFDStruct.Function = SourceMat.Function;
                HFDStruct.HeadModelType = SourceMat.HeadModelType;
                HFDStruct.HeadModelFile = SourceMat.HeadModelFile
                HFDStruct.SurfaceFile = SourceMat.SurfaceFile;
                HFDStruct.Atlas = SourceMat.Atlas;
                HFDStruct.GridOrient = SourceMat.GridOrient;
                HFDStruct.GridLoc = SourceMat.GridLoc;
                HFDStruct.GoodChannel = SourceMat.GoodChannel;
                HFDStruct.History = {datetime('now'), 'Computed HFD for sources'};
                HFDStruct.CreatedBy = 'process_hfd';
                %Save source file
                [sStudy, iStudy] = bst_process('GetOutputStudy', sProcess, sInputs(iInput));
                OutputFile = bst_process('GetNewFilename', bst_fileparts(sStudy.FileName), 'results_HFD');
                bst_save(OutputFile, HFDStruct, 'v6', 0);
                %Register file in database
                db_add_data(iStudy, OutputFile, HFDStruct);
                OutputFiles{end+1} = OutputFile;
        end
    end
    %Reload the database for all processed studies
    uniqueStudies = unique([sInputs.iStudy]);
    db_reload_studies(uniqueStudies);
end

%% ===COMPUTE HFD FUNCTION===
function HFD = compute_hfd(dataeeg, k_max)
%***INPUT***
% - dataeeg: EEG time series vector
% - k_max: Maximum value of k parameter (65 in the paper)

N = length(dataeeg); 
if nargin < 2
    %Default value of k_max
    k_max = 65;
else
    k_max = k_max;
end

L = zeros(k_max, 1); %Vector to store the calculated lengths

%Iterations for each value of k
for k = 1:k_max
    Lk_sum = 0; % Paramater to accumulate the lengths of each segment

    %Iterate over the m values (initial offsets)
    for m = 1: k
        Lm_k = 0;
        num_segments = floor((N-m)/k); %number of segments with this k
    
        %Calculate the lenght of the segment with k pass and offset m
        for i = 1: num_segments
            Lm_k = Lm_k + abs(dataeeg(m + i * k) - dataeeg(m + (i-1)*k));
        end
    
        %Normalize Lm_k dividing by the number of segments and k
        Lm_k = (Lm_k * (N - 1) / (num_segments * k));
        Lk_sum = Lk_sum + Lm_k; 
    end

    %Mean of Lm_k for each value of k
    L(k)= Lk_sum / (k^2);
end


%Adjust Higuchi's Fractal Dimension using a linear regresion
log_k = log(1:k_max);
log_L = log(L);

%Linear fitting: The negative value of the slope is the fractal dimension
p = polyfit(log_k, log_L, 1);
HFD = -p(1);
end