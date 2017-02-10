% Class that collects "processing functions" as public static methods. See data_manager.m.
% dm = data_manager
% 
% Author: Erik P G Johansson, IRF-U, Uppsala, Sweden
% First created 2017-02-10, with source code from data_manager.m.
%
% This class is not meant to be instantiated. Its functions are only meant to be called from data_manager.
% May contain some non-trivial helper functions.
%
%
% CODE CONVENTIONS
% ================
% - Processing functions follow a convention for return values and arguments. See data_manager.get_processing_info. 
% - It is implicit that arrays/matrices representing CDF data, or "CDF-like" data, use the first MATLAB array index to
%   represent CDF records.
%
%
% SOME PDVs
% =========
% - Pre-Demuxing-Calibration Data (PreDCD)
%       Generic data format that can represent all forms of input datasets before demuxing and calibration.
%       Can use an arbitrary number of samples per record.
%       Consists of struct with fields:
%           .Epoch
%           .ACQUISITION_TIME
%           .DemuxerInput : struct with fields.
%               BIAS_1 to .BIAS_5  : NxM arrays, where M may be 1 (1 sample/record) or >1.
%           .freqHz                : Snapshot frequency in Hz. Unimportant for one sample/record data.
%           .DIFF_GAIN
%           .MUX_SET
%           QUALITY_FLAG
%           QUALITY_BITMASK
%           DELTA_PLUS_MINUS
%           (.SAMP_DTIME  ?)
%       Fields are "CDF-like": rows=records, all have same number of rows.
% - Post-Demuxing-Calibration Data (PostDCD)
%       Like PreDCD but with additional fields. Tries to capture a superset of the information that goes into any
%       dataset produced by BICAS.
%       Has extra fields:
%           .DemuxerOutput   : struct with fields.
%               V1, V2, V3,   V12, V13, V23,   V12_AC, V13_AC, V23_AC.
%           .IBIAS1
%           .IBIAS2
%           .IBIAS3
%
%
classdef dm_processing_functions
%#######################################################################################################################
% PROPOSAL: Move out calibration (not demuxing) from data_manager.
%   PROPOSAL: Reading of calibration files.
%   PROPOSAL: Function for calibrating with either constant factors and transfer functions. (Flag for choosing which.)
%       NOTE: Function needs enough information to split up data into sequences on which transfer functions can be applied.
%
% PROPOSAL: Use double for all numeric zVariables in the processing. Do not produce or require proper type, e.g. integers, in any
%           intermediate processing. Only convert to the proper data type/class when writing to CDF.
%   PRO: Variables can keep NaN to represent fill/pad value, also for "integers".
%   PRO: The knowledge of the dataset CDF formats is not spread out over the code.
%       Ex: Setting default values for PreDcd.QUALITY_FLAG, PreDcd.QUALITY_BITMASK, PreDcd.DELTA_PLUS_MINUS.
%       Ex: ACQUISITION_TIME.
%   CON: Less assertions can be made in utility functions.
%       Ex: dm_utils.ACQUISITION_TIME_*, dm_utils.tt2000_* functions.
%   CON: ROUNDING ERRORS. Can not be certain that values which are copied, are actually copied.
%   --
%   NOTE: Functions may in principle require integer math to work correctly.
%
% PROPOSAL: Comment section for intermediate PDVs.
% --
% PROPOSAL: Derive DIFF_GAIN (from BIAS HK using time interpolation) in one code common to both LFR & TDS.
%   PROPOSAL: Function
%   PROPOSAL: In intermediate PDV?!
%   PRO: Uses flag for selecting interpolation time in one place.
% PROPOSAL: Derive HK_BIA_MODE_MUX_SET (from BIAS SCI or HK using time interpolation for HK) in one code common to both LFR & TDS.
%   PROPOSAL: Function
%   PROPOSAL: In intermediate PDV?!
%   PRO: Uses flag for selecting HK/SCI DIFF_GAIN in one place.
%   PRO: Uses flag for selecting interpolation time in one place.
%--
% NOTE: Both BIAS HK and LFR SURV CWF contain MUX data (only LFR has one timestamp per snapshot). True also for other input datasets?
%#######################################################################################################################
    
    methods(Static, Access=public)
        
        function hkOnSciTimePd = process_HK_to_HK_on_SCI_TIME(InputsMap)
        % Processing function
        
            global CONSTANTS
            
            SciPd   = InputsMap('SCI_cdf').pd;
            HkPd    = InputsMap('HK_cdf').pd;
            
            hkOnSciTimePd = [];
            
            
            
            % Define local convenience variables. AT = ACQUISITION_TIME
            hkAtTt2000  = bicas.dm_utils.ACQUISITION_TIME_to_tt2000(  HkPd.ACQUISITION_TIME );
            sciAtTt2000 = bicas.dm_utils.ACQUISITION_TIME_to_tt2000( SciPd.ACQUISITION_TIME );
            hkEpoch     = HkPd.Epoch;
            sciEpoch    = SciPd.Epoch;
            
            %==================================================================
            % Log time intervals to enable comparing available SCI and HK data
            %==================================================================
            bicas.dm_utils.log_tt2000_interval('HK  ACQUISITION_TIME', hkAtTt2000)
            bicas.dm_utils.log_tt2000_interval('SCI ACQUISITION_TIME', sciAtTt2000)
            bicas.dm_utils.log_tt2000_interval('HK  Epoch           ', hkEpoch)
            bicas.dm_utils.log_tt2000_interval('SCI Epoch           ', sciEpoch)
            
            %=========================================================================================================
            % 1) Convert time to something linear in time that can be used for processing (not storing time to file).
            % 2) Effectively also chooses which time to use for the purpose of processing:
            %    ACQUISITION_TIME or Epoch.
            %=========================================================================================================
            if CONSTANTS.C.PROCESSING.USE_AQUISITION_TIME_FOR_HK_TIME_INTERPOLATION 
                irf.log('n', 'Using HK & SCI zVariable ACQUISITION_TIME (not Epoch) for interpolating HK data to SCI time.')
                hkInterpolationTimeTt2000  = hkAtTt2000;
                sciInterpolationTimeTt2000 = sciAtTt2000;
            else
                %irf.log('n', 'Using HK & SCI zVariable Epoch (not ACQUISITION_TIME) for interpolating HK data to SCI time.')
                hkInterpolationTimeTt2000  = hkEpoch;
                sciInterpolationTimeTt2000 = sciEpoch;
            end



            %=========================================================================================================
            % Choose where to get MUX_SET from: BIAS-HK, or possibly LFR-SCI
            % --------------------------------------------------------------
            % NOTE: Only obtains one MUX_SET per record ==> Can not change MUX_SET in the middle of a record.
            %=========================================================================================================            
            hkOnSciTimePd.MUX_SET = bicas.dm_utils.nearest_interpolate_float_records(...
                double(HkPd.HK_BIA_MODE_MUX_SET), hkInterpolationTimeTt2000, sciInterpolationTimeTt2000);   % Use BIAS HK.
            %PreDcd.MUX_SET = LFR_cdf.BIAS_MODE_MUX_SET;    % Use LFR SCI. NOTE: Only possible for ___LFR___.



            %=========================================================================================================
            % Derive approximate DIFF_GAIN values for from BIAS HK
            %
            % NOTE: Not perfect handling of time when 1 snapshot/record, since one should ideally use time stamps
            % for every LFR _sample_.
            %=========================================================================================================
            hkOnSciTimePd.DIFF_GAIN = bicas.dm_utils.nearest_interpolate_float_records(...
                double(HkPd.HK_BIA_DIFF_GAIN), hkInterpolationTimeTt2000, sciInterpolationTimeTt2000);
            
            
            
            %error('BICAS:data_manager:OperationNotImplemented', ...
            %    'This processing function process_HK_to_HK_on_SCI_TIME has not been implemented yet.')
        end        
        
        

        function PreDcd = process_LFR_to_PreDCD(InputsMap)
        % Processing function. Convert LFR CDF data (PDs) to PreDCD.
        %
        % Keeps number of samples/record. Treats 1 samples/record "length-one snapshots".
        
        % PROBLEM: Hardcoded CDF data types (MATLAB classes).
        
            sciPdid       = InputsMap('SCI_cdf').pdid;
            SciPd         = InputsMap('SCI_cdf').pd;
            HkOnSciTimePd = InputsMap('HK_on_SCI_time').pd;

            nRecords = size(SciPd.Epoch, 1);
            
            %=====================================================================
            % Handle differences between skeletons V01 and V02
            % ------------------------------------------------
            % LFR_V, LFR_E: zVars with different names (but identical meaning).
            % L1_REC_NUM  : Not defined in V01, but in V02 dataset skeletons.
            %=====================================================================
            switch(sciPdid)
                case {  'L2R_LFR-SBM1-CWF_V01', ...
                        'L2R_LFR-SBM2-CWF_V01', ...
                        'L2R_LFR-SURV-CWF_V01', ...
                        'L2R_LFR-SURV-SWF_V01'}
                    POTENTIAL  = SciPd.POTENTIAL;
                    ELECTRICAL = SciPd.ELECTRICAL;
                    L1_REC_NUM = NaN * zeros(nRecords, 1);   % Set to fill values.
                case {  'L2R_LFR-SBM1-CWF_V02', ...
                        'L2R_LFR-SBM2-CWF_V02', ...
                        'L2R_LFR-SURV-CWF_V02', ...
                        'L2R_LFR-SURV-SWF_V02'}
                    POTENTIAL  = SciPd.V;
                    ELECTRICAL = SciPd.E;
                    L1_REC_NUM = SciPd.L1_REC_NUM;
                otherwise
                    error('BICAS:data_manager:SWModeProcessing:Assertion:ConfigurationBug', ...
                        'Can not handle PDID="%s"', sciPdid)
            end
            
            %========================================================================================
            % Handle differences between datasets with and without zVAR FREQ:
            % LFR_FREQ: Corresponds to FREQ only defined in some LFR datasets.
            %========================================================================================
            switch(sciPdid)
                case {  'L2R_LFR-SBM1-CWF_V01', ...
                        'L2R_LFR-SBM1-CWF_V02'}
                    FREQ = ones(nRecords, 1) * 1;   % Always value "1".
                case {  'L2R_LFR-SBM2-CWF_V01', ...
                        'L2R_LFR-SBM2-CWF_V02'}
                    FREQ = ones(nRecords, 1) * 2;   % Always value "2".
                case {  'L2R_LFR-SURV-CWF_V01', ...
                        'L2R_LFR-SURV-CWF_V02', ...
                        'L2R_LFR-SURV-SWF_V01', ...
                        'L2R_LFR-SURV-SWF_V02'}
                    FREQ = SciPd.FREQ;
                otherwise
                    error('BICAS:data_manager:SWModeProcessing:Assertion:ConfigurationBug', ...
                        'Can not handle PDID="%s"', sciPdid)
            end
            
            nSamplesPerRecord = size(POTENTIAL, 2);
            freqHz            = bicas.dm_utils.get_LFR_frequency( FREQ );   % NOTE: Needed also for 1 SPR.
            
            % Find the relevant value of zVariables R0, R1, R2, "R3".
            Rx = bicas.dm_utils.get_LFR_Rx( SciPd.R0, SciPd.R1, SciPd.R2, FREQ );   % NOTE: Function also handles the imaginary zVar "R3".
            
            PreDcd = [];
            PreDcd.Epoch            = SciPd.Epoch;
            PreDcd.ACQUISITION_TIME = SciPd.ACQUISITION_TIME;
            PreDcd.DELTA_PLUS_MINUS = bicas.dm_utils.derive_DELTA_PLUS_MINUS(freqHz, nSamplesPerRecord);            
            PreDcd.freqHz           = freqHz;
            PreDcd.SAMP_DTIME       = bicas.dm_utils.derive_SAMP_DTIME(freqHz, nSamplesPerRecord);            
            PreDcd.L1_REC_NUM       = L1_REC_NUM;
            
            %===========================================================================================================
            % Replace illegally empty data with fill values/NaN
            % -------------------------------------------------
            % IMPLEMENTATION NOTE: QUALITY_FLAG, QUALITY_BITMASK have been found empty in test data, but should have
            % attribute DEPEND_0 = "Epoch" ==> Should have same number of records as Epoch.
            % Can not save CDF with zVar with zero records (crashes when reading CDF). ==> Better create empty records.
            % Test data: MYSTERIOUS_SIGNAL_1_2016-04-15_Run2__7729147__CNES/ROC-SGSE_L2R_RPW-LFR-SURV-SWF_7729147_CNE_V01.cdf
            %===========================================================================================================
            PreDcd.QUALITY_FLAG    = SciPd.QUALITY_FLAG;
            PreDcd.QUALITY_BITMASK = SciPd.QUALITY_BITMASK;
            if isempty(PreDcd.QUALITY_FLAG)
                irf.log('w', 'QUALITY_FLAG from the SCI source dataset is empty. Filling with empty values.')
                PreDcd.QUALITY_FLAG    = NaN * zeros([nRecords, 1]);
            end
            if isempty(PreDcd.QUALITY_BITMASK)
                irf.log('w', 'QUALITY_BITMASK from the SCI source dataset is empty. Filling with empty values.')
                PreDcd.QUALITY_BITMASK = NaN * zeros([nRecords, 1]);
            end
            
            PreDcd.DemuxerInput        = [];
            PreDcd.DemuxerInput.BIAS_1 = POTENTIAL;
            PreDcd.DemuxerInput.BIAS_2 = bicas.dm_utils.filter_rows( ELECTRICAL(:,:,1), Rx==1 );
            PreDcd.DemuxerInput.BIAS_3 = bicas.dm_utils.filter_rows( ELECTRICAL(:,:,2), Rx==1 );
            PreDcd.DemuxerInput.BIAS_4 = bicas.dm_utils.filter_rows( ELECTRICAL(:,:,1), Rx==0 );
            PreDcd.DemuxerInput.BIAS_5 = bicas.dm_utils.filter_rows( ELECTRICAL(:,:,2), Rx==0 );
            
            PreDcd.MUX_SET   = HkOnSciTimePd.MUX_SET;
            PreDcd.DIFF_GAIN = HkOnSciTimePd.DIFF_GAIN;

            
            
            % ASSERTIONS
            bicas.dm_utils.assert_unvaried_N_rows(PreDcd);
            bicas.dm_utils.assert_unvaried_N_rows(PreDcd.DemuxerInput);
        end
        
        
        
        function PreDcd = process_TDS_to_PreDCD(InputsMap)
        % UNTESTED
        %
        % Processing function. Convert TDS CDF data (PDs) to PreDCD.
        %
        % Keeps number of samples/record. Treats 1 samples/record "length-one snapshots".
        
        % NOTE: L1_REC_NUM not set in any TDS L2R dataset
        
            % global CONSTANTS
        
            SciPd         = InputsMap('SCI_cdf').pd;
            HkOnSciTimePd = InputsMap('HK_on_SCI_time').pd;
            sciPdid       = InputsMap('SCI_cdf').pdid;

            %=====================================================================
            % Handle differences between skeletons V01 and V02
            % ------------------------------------------------
            % LFR_V, LFR_E: zVars with different names (but identical meaning).
            % L1_REC_NUM  : Not defined in V01, but in V02 dataset skeletons.
            %=====================================================================
            switch(sciPdid)
                % Those TDS datasets which have the SAME number of samples/record as in the output datasets.
                case {'L2R_TDS-LFM-CWF_V01', ...     % 1 S/R
                      'L2R_TDS-LFM-RSWF_V02'};       % N S/R
                      
                % Those TDS datasets which have DIFFERENT number of samples/record compared to the output datasets.
                case {'L2R_TDS-LFM-RSWF_V01'}        % 1 S/R for SWF data!!!
                    error('BICAS:data_manager:SWModeProcessing:Assertion:OperationNotImplemented', ...
                        'This processing function can not interpret PDID=%s. Not implemented yet.', sciPdid)
                otherwise
                    error('BICAS:data_manager:SWModeProcessing:Assertion:ConfigurationBug', ...
                        'Can not handle PDID="%s"', sciPdid)
            end
            
            nRecords          = size(SciPd.Epoch, 1);
            nSamplesPerRecord = size(SciPd.WAVEFORM_DATA, 3);
            
            freqHz = SciPd.SAMPLING_RATE;
            
            PreDcd = [];
            
            PreDcd.Epoch            = SciPd.Epoch;
            PreDcd.ACQUISITION_TIME = SciPd.ACQUISITION_TIME;
            PreDcd.DELTA_PLUS_MINUS = bicas.dm_utils.derive_DELTA_PLUS_MINUS(freqHz, nSamplesPerRecord);            
            PreDcd.freqHz           = freqHz;    % CDF_UINT1 ?!!!
            PreDcd.SAMP_DTIME       = bicas.dm_utils.derive_SAMP_DTIME(freqHz, nSamplesPerRecord);
            PreDcd.L1_REC_NUM       = NaN * zeros(nRecords, nSamplesPerRecord);   % Set to fill values. Not set in any TDS L2R dataset yet.

            PreDcd.QUALITY_FLAG    = SciPd.QUALITY_FLAG;
            PreDcd.QUALITY_BITMASK = SciPd.QUALITY_BITMASK;
            
            PreDcd.DemuxerInput        = [];
            PreDcd.DemuxerInput.BIAS_1 = permute(SciPd.WAVEFORM_DATA(:,1,:), [1,3,2]);
            PreDcd.DemuxerInput.BIAS_2 = permute(SciPd.WAVEFORM_DATA(:,2,:), [1,3,2]);
            PreDcd.DemuxerInput.BIAS_3 = permute(SciPd.WAVEFORM_DATA(:,3,:), [1,3,2]);
            PreDcd.DemuxerInput.BIAS_4 = NaN*zeros([nRecords, nSamplesPerRecord]);
            PreDcd.DemuxerInput.BIAS_5 = NaN*zeros([nRecords, nSamplesPerRecord]);
            
            PreDcd.MUX_SET   = HkOnSciTimePd.MUX_SET;
            PreDcd.DIFF_GAIN = HkOnSciTimePd.DIFF_GAIN;
            
            
            
            % ASSERTIONS
            bicas.dm_utils.assert_unvaried_N_rows(PreDcd);
            bicas.dm_utils.assert_unvaried_N_rows(PreDcd.DemuxerInput);
            
            %error('BICAS:data_manager:OperationNotImplemented', ...
            %    'This processing function process_TDS_to_PreDCD has not been implemented yet.')
        end

        

        function assert_PreDCD(PreDcd)
            FIELDS = {'Epoch', 'ACQUISITION_TIME', 'DemuxerInput', 'freqHz', 'DIFF_GAIN', 'MUX_SET', 'QUALITY_FLAG', ...
                'QUALITY_BITMASK', 'DELTA_PLUS_MINUS', 'L1_REC_NUM', 'SAMP_DTIME'};
            
            if ~isstruct(PreDcd) || ~isempty(setxor(fieldnames(PreDcd), FIELDS))
                error('BICAS:data_manager:Assertion:SWModeProcessing', 'PDV structure is not on "PreDCD format".')
            end
            bicas.dm_utils.assert_unvaried_N_rows(PreDcd);
        end
        
        
        
        function assert_PostDCD(PostDcd)
            FIELDS = {'Epoch', 'ACQUISITION_TIME', 'DemuxerInput', 'freqHz', 'DIFF_GAIN', 'MUX_SET', 'QUALITY_FLAG', ...
                'QUALITY_BITMASK', 'DELTA_PLUS_MINUS', 'DemuxerOutput', 'IBIAS1', 'IBIAS2', 'IBIAS3', 'L1_REC_NUM', 'SAMP_DTIME'};
            
            if ~isstruct(PostDcd) || ~isempty(setxor(fieldnames(PostDcd), FIELDS))
                error('BICAS:data_manager:Assertion:SWModeProcessing', 'PDV structure is not on "PostDCD format".')
            end
            bicas.dm_utils.assert_unvaried_N_rows(PostDcd);
        end
        
        

        function PostDcd = process_demuxing_calibration(InputsMap)
        % Processing function. Converts PreDCD to PostDCD, i.e. demux and calibrate data.
        
            PreDcd = InputsMap('PreDCD').pd;
            bicas.dm_processing_functions.assert_PreDCD(PreDcd);
                    
            % Log messages
            for f = fieldnames(PreDcd.DemuxerInput)'
                bicas.dm_utils.log_values_summary(f{1}, PreDcd.DemuxerInput.(f{1}));
            end
            
            PostDcd = PreDcd;
            
            %=======
            % DEMUX
            %=======
            PostDcd.DemuxerOutput = bicas.dm_processing_functions.simple_demultiplex(...
                PreDcd.DemuxerInput, PreDcd.MUX_SET, PreDcd.DIFF_GAIN);
            
            % Log messages
            for f = fieldnames(PostDcd.DemuxerOutput)'
                bicas.dm_utils.log_values_summary(f{1}, PostDcd.DemuxerOutput.(f{1}));
            end
            
            % BUG / TEMP: Set default values since the real values are not available.
            % Move "derivation" to HK_on_SCI_time?
            PostDcd.IBIAS1 = NaN * zeros(size(PostDcd.DemuxerOutput.V1));
            PostDcd.IBIAS2 = NaN * zeros(size(PostDcd.DemuxerOutput.V2));
            PostDcd.IBIAS3 = NaN * zeros(size(PostDcd.DemuxerOutput.V3));
            
            bicas.dm_processing_functions.assert_PostDCD(PostDcd)
        end
        

        
        function EOutPD = process_PostDCD_to_LFR(InputsMap, eoutPDID)
        % Processing function. Convert PostDCD to any one of several similar LFR dataset PDs.
        
            PostDcd = InputsMap('PostDCD').pd;
            EOutPD = [];
            
            nSamplesPerRecord = size(PostDcd.DemuxerOutput.V1, 2);   % Samples per record.
            
            switch(eoutPDID)
                case  {'L2S_LFR-SBM1-CWF-E_V02', ...
                       'L2S_LFR-SBM2-CWF-E_V02', ...
                       'L2S_LFR-SURV-CWF-E_V02'}
                    
                    %=====================================================================
                    % Convert 1 snapshot/record --> 1 sample/record (if not already done)
                    %=====================================================================
                    EOutPD.Epoch = bicas.dm_utils.convert_N_to_1_SPR_Epoch( ...
                        PostDcd.Epoch, ...
                        nSamplesPerRecord, ...
                        PostDcd.freqHz  );
                    EOutPD.ACQUISITION_TIME = bicas.dm_utils.convert_N_to_1_SPR_ACQUISITION_TIME(...
                        PostDcd.ACQUISITION_TIME, ...
                        nSamplesPerRecord, ...
                        PostDcd.freqHz  );
                    
                    EOutPD.DELTA_PLUS_MINUS = bicas.dm_utils.convert_N_to_1_SPR_redistribute( PostDcd.DELTA_PLUS_MINUS );
                    EOutPD.L1_REC_NUM       = bicas.dm_utils.convert_N_to_1_SPR_repeat(       PostDcd.L1_REC_NUM,      nSamplesPerRecord);
                    EOutPD.QUALITY_FLAG     = bicas.dm_utils.convert_N_to_1_SPR_repeat(       PostDcd.QUALITY_FLAG,    nSamplesPerRecord);
                    EOutPD.QUALITY_BITMASK  = bicas.dm_utils.convert_N_to_1_SPR_repeat(       PostDcd.QUALITY_BITMASK, nSamplesPerRecord);
                    % F_SAMPLE, SAMP_DTIME: Omitting. Are not supposed to be present in BIAS CWF datasets.
                    
                    % Convert PostDcd.DemuxerOutput
                    for fn = fieldnames(PostDcd.DemuxerOutput)'
                        PostDcd.DemuxerOutput.(fn{1}) = bicas.dm_utils.convert_N_to_1_SPR_redistribute( ...
                            PostDcd.DemuxerOutput.(fn{1}) );
                    end
                    
                    EOutPD.IBIAS1           = bicas.dm_utils.convert_N_to_1_SPR_redistribute( PostDcd.IBIAS1 );
                    EOutPD.IBIAS2           = bicas.dm_utils.convert_N_to_1_SPR_redistribute( PostDcd.IBIAS2 );
                    EOutPD.IBIAS3           = bicas.dm_utils.convert_N_to_1_SPR_redistribute( PostDcd.IBIAS3 );

                case  'L2S_LFR-SURV-SWF-E_V02'
                    
                    % ASSERTION
                    if nSamplesPerRecord ~= 2048
                        error('BICAS:data_manager:Assertion:IllegalArgument', 'Number of samples per CDF record is not 2048.')
                    end
                    
                    EOutPD.Epoch            = PostDcd.Epoch;
                    EOutPD.ACQUISITION_TIME = PostDcd.ACQUISITION_TIME;                    
                    
                    EOutPD.DELTA_PLUS_MINUS = PostDcd.DELTA_PLUS_MINUS;
                    EOutPD.L1_REC_NUM       = PostDcd.L1_REC_NUM;
                    EOutPD.QUALITY_BITMASK  = PostDcd.QUALITY_BITMASK;
                    EOutPD.QUALITY_FLAG     = PostDcd.QUALITY_FLAG;
                    
                    % Only in LFR SWF (not CWF): F_SAMPLE, SAMP_DTIME
                    EOutPD.F_SAMPLE         = PostDcd.freqHz;
                    EOutPD.SAMP_DTIME       = PostDcd.SAMP_DTIME;

                    EOutPD.IBIAS1           = PostDcd.IBIAS1;
                    EOutPD.IBIAS2           = PostDcd.IBIAS2;
                    EOutPD.IBIAS3           = PostDcd.IBIAS3;
                    
                otherwise
                    error('BICAS:data_manager:Assertion:IllegalArgument', 'Function can not produce PDID=%s.', eoutPDID)
            end
            
            EOutPD.V(:,:,1)         = PostDcd.DemuxerOutput.V1;
            EOutPD.V(:,:,2)         = PostDcd.DemuxerOutput.V2;
            EOutPD.V(:,:,3)         = PostDcd.DemuxerOutput.V3;
            EOutPD.E(:,:,1)         = PostDcd.DemuxerOutput.V12;
            EOutPD.E(:,:,2)         = PostDcd.DemuxerOutput.V13;
            EOutPD.E(:,:,3)         = PostDcd.DemuxerOutput.V23;
            EOutPD.EAC(:,:,1)       = PostDcd.DemuxerOutput.V12_AC;
            EOutPD.EAC(:,:,2)       = PostDcd.DemuxerOutput.V13_AC;
            EOutPD.EAC(:,:,3)       = PostDcd.DemuxerOutput.V23_AC;
            
            % ASSERTION            
            bicas.dm_utils.assert_unvaried_N_rows(EOutPD);
        end   % process_PostDCD_to_LFR



        function EOutPD = process_PostDCD_to_TDS(InputsMap, eoutPDID)

            %switch(eoutPDID)
            %    case  'L2S_TDS-LFM-CWF-E_V02'
            %    case  'L2S_TDS-LFM-RSWF-E_V02'
                        
                    
            error('BICAS:data_manager:SWModeProcessing:Assertion:OperationNotImplemented', ...
                'This processing function has not been implemented yet.')
        end    
        
    end   % methods(Static, Access=public)
            
    %###################################################################################################################
    
    methods(Static, Access=private)
        
        function DemuxerOutput = simple_demultiplex(DemuxerInput, MUX_SET, DIFF_GAIN)
        % Wrapper around "simple_demultiplex_subsequence" to be able to handle multiple CDF records with changing
        % settings (mux_set, diff_gain).
        %
        % NOTE: NOT a processing function (does not derive a PDV).
        %
        % ARGUMENTS AND RETURN VALUE
        % ==========================
        % mux_set   = Column vector. Numbers identifying the MUX/DEMUX mode. 
        % input     = Struct with fields BIAS_1 to BIAS_5.
        % diff_gain = Column vector. Gains for differential measurements. 0 = Low gain, 1 = High gain.
        %
        % NOTE: Can handle any arrays of any size as long as the sizes are consistent.
        
            bicas.dm_utils.assert_unvaried_N_rows(DemuxerInput)
            nRecords = length(MUX_SET);
            
            % Create empty structure to which new components can be added.
            DemuxerOutput = struct(...
                'V1',     [], 'V2',     [], 'V3',     [], ...
                'V12',    [], 'V23',    [], 'V13',    [], ...
                'V12_AC', [], 'V23_AC', [], 'V13_AC', []);
            
            iFirst = 1;    % First record in sequence of records with constant settings.
            while iFirst <= nRecords;
                
                % Find continuous sequence of records (i_first to i_last) having identical settings.
                iLast = bicas.dm_utils.find_last_same_sequence(iFirst, DIFF_GAIN, MUX_SET);
                MUX_SET_value   = MUX_SET  (iFirst);
                DIFF_GAIN_value = DIFF_GAIN(iFirst);
                irf.log('n', sprintf('Records %2i-%2i : Demultiplexing; MUX_SET=%-3i; DIFF_GAIN=%-3i', ...
                    iFirst, iLast, MUX_SET_value, DIFF_GAIN_value))    % "%-3" since value might be NaN.
                
                % Extract subsequence of records to "demux".
                demuxerInputSubseq = bicas.dm_utils.select_subset_from_struct(DemuxerInput, iFirst, iLast);
                
                %=================================================
                % CALL DEMUXER - See method/function for comments
                %=================================================
                demuxerOutputSubseq = bicas.dm_processing_functions.simple_demultiplex_subsequence(demuxerInputSubseq, MUX_SET_value, DIFF_GAIN_value);
                
                % Add demuxed sequence to the to-be complete set of records.
                DemuxerOutput = bicas.dm_utils.add_components_to_struct(DemuxerOutput, demuxerOutputSubseq);
                
                iFirst = iLast + 1;
                
            end   % while
            
        end   % simple_demultiplex

        
        
        function Output = simple_demultiplex_subsequence(Input, MUX_SET, DIFF_GAIN)
        % simple_demultiplex_subsequence   Demultiplex, with only constant factors for calibration (no transfer
        % functions, no offsets) and only one setting for MUX_SET and DIFF_GAIN respectively.
        %
        % This function implements Table 3 and Table 4 in "RPW-SYS-MEB-BIA-SPC-00001-IRF", iss1rev16.
        % Variable names are chosen according to these tables.
        %
        % NOTE: Conceptually, this function mixes demuxing with calibration which can (and most likely should) be separated.
        % - Demuxing is done on individual samples at a specific point in time.
        % - Calibration (with transfer functions) is made on a time series (presumably of one variable, but could be several).
        %
        % NOTE: This function can only handle one value for mux
        % NOTE: Function is intended for development/testing until there is proper code for using transfer functions.
        % NOTE: "input"/"output" refers to input/output for the function, which is (approximately) the opposite of
        % the physical signals in the BIAS hardware.
        %
        %
        % ARGUMENTS AND RETURN VALUE
        % ==========================
        % Input     : Struct with fields BIAS_1 to BIAS_5.
        % MUX_SET   : Scalar number identifying the MUX/DEMUX mode.
        % DIFF_GAIN : Scalar gain for differential measurements. 0 = Low gain, 1 = High gain.
        % Output    : Struct with fields V1, V2, V3,   V12, V13, V23,   V12_AC, V13_AC, V23_AC.
        % 
        % NOTE: Will tolerate values of NaN for MUX_SET_value, DIFF_GAIN_value. The effect is NaN in the corresponding output values.
        %
        % NOTE: Can handle any arrays of any size as long as the sizes are consistent.

        
            %==========================================================================================================
            % QUESTION: How to structure the demuxing?
            % --
            % QUESTION: How split by record? How put together again? How do in a way which
            %           works for real transfer functions? How handle the many non-indexed outputs?
            % QUESTION: How handle changing values of diff_gain, mux_set, bias-dependent calibration offsets?
            % NOTE: LFR data can be either 1 sample/record or 1 snapshot/record.
            % PROPOSAL: Work with some subset of in- and out-values of each type?
            %   PROPOSAL: Work with exactly one value of each type?
            %       CON: Slow.
            %           CON: Only temporary implementation.
            %       PRO: Quick to implement.
            %   PROPOSAL: Work with only some arbitrary subset specified by array of indices.
            %   PROPOSAL: Work with only one row?
            %   PROPOSAL: Work with a continuous sequence of rows/records?
            %   PROPOSAL: Submit all values, and return structure. Only read and set subset specified by indices.
            %
            %
            % PROPOSAL: Could, maybe, be used for demuxing if the caller has already applied the
            % transfer function calibration on on the BIAS signals.
            % PROPOSAL: Validate with some "multiplexer" function?!
            % QUESTION: How handle overdetermined systems one gets when one probe fails?
            % QUESTION: Does it make sense to have BIAS values as cell array? Struct fields?!
            %   PRO: Needed for caller's for loop to split up by record.
            %
            % QUESTION: Is there some better way of implementing than giant switch statement?!
            %
            % PROPOSAL: Only work for scalar values of mux_set and diff_gain?
            % QUESTION: MUX mode 1-3 are overdetermined if we always have BIAS1-3?
            %           If so, how select what to calculate?! What if results disagree/are inconsistent? Check for it?
            %
            % PROPOSAL: Move translation diff_gain-->gamma to separate function (cf. dm_utils.get_LFR_frequency).
            %==========================================================================================================
            
            global CONSTANTS
            
            % ASSERTIONS
            if numel(MUX_SET) ~= 1 || numel(DIFF_GAIN) ~= 1
                error('BICAS:data_manager:Assertion:IllegalArgument', 'Illegal argument value "mux_set" or "diff_gain". Must be scalars (not arrays).')
            end
            
            ALPHA = CONSTANTS.C.SIMPLE_DEMUXER.ALPHA;
            BETA  = CONSTANTS.C.SIMPLE_DEMUXER.BETA;
            switch(DIFF_GAIN)
                case 0    ; GAMMA = CONSTANTS.C.SIMPLE_DEMUXER.GAMMA_LOW_GAIN;
                case 1    ; GAMMA = CONSTANTS.C.SIMPLE_DEMUXER.GAMMA_HIGH_GAIN;
                otherwise
                    if isnan(DIFF_GAIN)
                        GAMMA = NaN;
                    else
                        error('BICAS:data_manager:Assertion:IllegalArgument:DatasetFormat', 'Illegal argument value "diff_gain"=%d.', DIFF_GAIN)                    
                    end
            end
            
            % Set default values which will remain for
            % variables which are not set by the demuxer.
            NAN_VALUES = ones(size(Input.BIAS_1)) * NaN;
            V1_LF     = NAN_VALUES;
            V2_LF     = NAN_VALUES;
            V3_LF     = NAN_VALUES;
            V12_LF    = NAN_VALUES;
            V13_LF    = NAN_VALUES;
            V23_LF    = NAN_VALUES;
            V12_LF_AC = NAN_VALUES;
            V13_LF_AC = NAN_VALUES;
            V23_LF_AC = NAN_VALUES;

            switch(MUX_SET)
                case 0   % "Standard operation" : We have all information.
                    
                    % Summarize the IN DATA we have.
                    V1_DC  = Input.BIAS_1;
                    V12_DC = Input.BIAS_2;
                    V23_DC = Input.BIAS_3;
                    V12_AC = Input.BIAS_4;
                    V23_AC = Input.BIAS_5;
                    % Derive the OUT DATA which are trivial.
                    V1_LF     = V1_DC  / ALPHA;
                    V12_LF    = V12_DC / BETA;
                    V23_LF    = V23_DC / BETA;
                    V12_LF_AC = V12_AC / GAMMA;
                    V23_LF_AC = V23_AC / GAMMA;
                    % Derive the OUT DATA which are less trivial.
                    V13_LF    = V12_LF    + V23_LF;
                    V2_LF     = V1_LF     - V12_LF;
                    V3_LF     = V2_LF     - V23_LF;                    
                    V13_LF_AC = V12_LF_AC + V23_LF_AC;
                    
                case 1   % Probe 1 fails
                    
                    V2_LF     = Input.BIAS_1 / ALPHA;
                    V3_LF     = Input.BIAS_2 / ALPHA;
                    V23_LF    = Input.BIAS_3 / BETA;
                    % input.BIAS_4 unavailable.
                    V23_LF_AC = Input.BIAS_5 / GAMMA;
                    
                case 2   % Probe 2 fails
                    
                    V1_LF     = Input.BIAS_1 / ALPHA;
                    V3_LF     = Input.BIAS_2 / ALPHA;
                    V13_LF    = Input.BIAS_3 / BETA;
                    V13_LF_AC = Input.BIAS_4 / GAMMA;
                    % input.BIAS_5 unavailable.
                    
                case 3   % Probe 3 fails
                    
                    V1_LF     = Input.BIAS_1 / ALPHA;
                    V2_LF     = Input.BIAS_2 / ALPHA;
                    V12_LF    = Input.BIAS_3 / BETA;
                    V12_LF_AC = Input.BIAS_4 / GAMMA;
                    % input.BIAS_5 unavailable.
                    
                case 4   % Calibration mode 0
                    
                    % Summarize the IN DATA we have.
                    V1_DC  = Input.BIAS_1;
                    V2_DC  = Input.BIAS_2;
                    V3_DC  = Input.BIAS_3;
                    V12_AC = Input.BIAS_4;
                    V23_AC = Input.BIAS_5;
                    % Derive the OUT DATA which are trivial.
                    V1_LF     = V1_DC / ALPHA;
                    V2_LF     = V2_DC / ALPHA;
                    V3_LF     = V3_DC / ALPHA;
                    V12_LF_AC = V12_AC / GAMMA;
                    V23_LF_AC = V23_AC / GAMMA;
                    % Derive the OUT DATA which are less trivial.
                    V12_LF    = V1_LF     - V2_LF;
                    V13_LF    = V1_LF     - V3_LF;
                    V23_LF    = V2_LF     - V3_LF;
                    V13_LF_AC = V12_LF_AC + V23_LF_AC;

                case {5,6,7}
                    error('BICAS:data_manager:Assertion:OperationNotImplemented', 'Not implemented for this value of mux_set yet.')
                    
                otherwise
                    if isnan(MUX_SET)
                        ;   % Do nothing. Allow the default values (NaN) to be returned.
                    else
                        error('BICAS:data_manager:Assertion:IllegalArgument:DatasetFormat', 'Illegal argument value for mux_set.')
                    end
            end   % switch
            
            % Create structure to return.
            Output = [];
            Output.V1     = V1_LF;
            Output.V2     = V2_LF;
            Output.V3     = V3_LF;
            Output.V12    = V12_LF;
            Output.V13    = V13_LF;
            Output.V23    = V23_LF;
            Output.V12_AC = V12_LF_AC;
            Output.V13_AC = V13_LF_AC;
            Output.V23_AC = V23_LF_AC;
            
        end  % simple_demultiplex_subsequence
        
    end   % methods(Static, Access=private)
        
end
