function export(ebsp,tint,cl_id,freqRange)
%EXPORT  Export data to CEF
%
% export( ebsp, tint, cl_id, freqRange)
%
% Will create a gzipped CEF file in the current directory

% ----------------------------------------------------------------------------
% "THE BEER-WARE LICENSE" (Revision 42):
% <yuri@irfu.se> wrote this file.  As long as you retain this notice you
% can do whatever you want with this stuff. If we meet some day, and you think
% this stuff is worth it, you can buy me a beer in return.   Yuri Khotyaintsev
% ----------------------------------------------------------------------------
%
% This software was developed as part of the MAARBLE (Monitoring,
% Analyzing and Assessing Radiation Belt Energization and Loss)
% collaborative research project which has received funding from the
% European Community's Seventh Framework Programme (FP7-SPACE-2011-1)
% under grant agreement n. 284520.

% This must be changed when we do any major changes to our processing software
DATASET_VERSION = '0';

% We do not track versions here, CAA will do this for us
DATA_VERSION = '00';

%% Check the input
if ~ebsp.flagFac, error('EBSP must be in FAC'), end
switch lower(freqRange)
    case 'pc12'
        %DT2 = 0.5; % time resolution
        datasetID = 'MAARBLE_ULF_PC12';
        numberOfFreq = 21;
    case 'pc35';
        %DT2 = 30; % time resolution
        datasetID = 'MAARBLE_ULF_PC35';
        numberOfFreq = 21;
    otherwise
        error('freqRange must be ''pc12'' or ''pc35''')
end
nFreq = length(ebsp.f); nData = length(ebsp.t);
if nFreq~=numberOfFreq
    error('number of frequencies in ebsp.f must be %d (not %d!)',...
        numberOfFreq,nFreq)
end

%% Prepare data array
% B0
if isempty(ebsp.fullB), magB = ebsp.B0; else magB = ebsp.fullB; end
magB = irf_abs(magB); magB = magB(:,[1 4]); magB = irf_resamp(magB,ebsp.t);

% convert radians to degrees
toD = 180.0/pi;
ebsp.k_tp(:,:,1:2) = ebsp.k_tp(:,:,1:2)*toD;
ebsp.pf_rtp(:,:,2:3) = ebsp.pf_rtp(:,:,2:3)*toD;

% fliplr to make frequencies ascending
ebsp.k_tp(:,:,1) = fliplr(ebsp.k_tp(:,:,1));
ebsp.k_tp(:,:,2) = fliplr(ebsp.k_tp(:,:,2));
ebsp.ellipticity = fliplr(ebsp.ellipticity);
ebsp.planarity = fliplr(ebsp.planarity);
ebsp.dop = fliplr(ebsp.dop);
ebsp.dop2d = fliplr(ebsp.dop2d);
ebsp.pf_rtp(:,:,1) = fliplr(ebsp.pf_rtp(:,:,1));
ebsp.pf_rtp(:,:,2) = fliplr(ebsp.pf_rtp(:,:,2));
ebsp.pf_rtp(:,:,3) = fliplr(ebsp.pf_rtp(:,:,3));
ebsp.ee_ss = fliplr(ebsp.ee_ss);

% Replace NaN with FILLVAL (specified in the CEF header)
FILLVAL            = -999;
FILLVAL_EXP        = -1.00E+31;

ebsp.k_tp(isnan(ebsp.k_tp)) = FILLVAL;
ebsp.ellipticity(isnan(ebsp.ellipticity)) = FILLVAL;
ebsp.planarity(isnan(ebsp.planarity)) = FILLVAL;
ebsp.dop(isnan(ebsp.dop)) = FILLVAL;
ebsp.dop2d(isnan(ebsp.dop2d)) = FILLVAL;
ebsp.pf_rtp(isnan(ebsp.pf_rtp(:,:,1))) = FILLVAL_EXP;
ebsp.pf_rtp(isnan(ebsp.pf_rtp)) = FILLVAL;
magB(isnan(magB)) = FILLVAL_EXP;
ebsp.planarity(isnan(ebsp.planarity)) = FILLVAL;
ebsp.bb_xxyyzzss(isnan(ebsp.bb_xxyyzzss)) = FILLVAL_EXP;
% Reformat B matrix and fliplr to make frequencies ascending
BB_2D = zeros(nData,nFreq*3);
for comp=1:3
    BB_2D(:,((1:nFreq)-1)*3+comp) = fliplr(ebsp.bb_xxyyzzss(:,:,comp)); 
end

% Define formats for output
formatExp = '%9.2e,'; % Amplitudes
formatAng = '%6.0f,'; % Angles - integer values
formatDeg = '%6.1f,'; % Degree of ... -1..1 or 0..1

% NOTE: This list must be consistent with the CEF header file
dataToExport = {...
    {formatExp, BB_2D},...              % BB_xxyyzz_fac
    {formatAng, ebsp.k_tp(:,:,1)},...   % THSVD_fac
    {formatAng, ebsp.k_tp(:,:,2)},...   % PHSVD_fac
    {formatDeg, ebsp.ellipticity},...   % ELLSVD
    {formatDeg, ebsp.planarity},...     % PLANSVD
    {formatDeg, ebsp.dop},...           % DOP
    {formatDeg, ebsp.dop2d},...         % POLSVD
    {formatExp, ebsp.pf_rtp(:,:,1)},... % AMPV
    {formatAng, ebsp.pf_rtp(:,:,2)},... % THPV
    {formatAng, ebsp.pf_rtp(:,:,3)},... % PHPV
    {formatExp, ebsp.ee_ss},...         % ESUM
    {formatExp, magB}                   % BMAG
    };

% For Pc3-5 we also add E spectrum in FAC
if strcmpi(freqRange,'pc35')
    ebsp.ee_xxyyzzss(isnan(ebsp.ee_xxyyzzss)) = FILLVAL_EXP;
    % Reformat E matrix and fliplr to make frequencies ascending
    EE_2D = zeros(nData,nFreq*3);
    for comp=1:3
        EE_2D(:,((1:nFreq)-1)*3+comp) = fliplr(ebsp.ee_xxyyzzss(:,:,comp)); 
    end
    dataToExport = [dataToExport {{formatExp, EE_2D}}]; % EE_xxyyzz_fac
end
    
% Time array goes first
out_CharArray = epoch2iso(ebsp.t,1); % Short ISO format: 2007-01-03T16:00:00.000Z
out_CharArray(:,end+1)=',';

% Write out data by columns and then combine into a common char matrix
for i=1:length(dataToExport)
    tmp_CharArray = sprintf(dataToExport{i}{1},dataToExport{i}{2}');
    tmp_CharArray = reshape(tmp_CharArray,length(tmp_CharArray)/nData,nData)';
    out_CharArray = [out_CharArray tmp_CharArray]; clear tmp_CharArray %#ok<AGROW>
end

% Add END_OF_RECORD markers in the end of each line
out_CharArray(:,end)='$';
out_CharArray(:,end+1)=sprintf('\n');
out_CharArray = out_CharArray';
out_CharArray=out_CharArray(:)';

%% Prepare the file header
fileName = [sprintf('C%d_CP_AUX_%s', cl_id, datasetID)...
    '__' irf_fname(tint,5) '_V' DATA_VERSION];
   
header = [...
    sprintf('!-------------------- CEF ASCII FILE --------------------|\n')...
    sprintf('! created on %s\n', datestr(now))...
    sprintf('!--------------------------------------------------------|\n')...
    sprintf('FILE_NAME = "%s.cef"\n',fileName)...
    sprintf('FILE_FORMAT_VERSION = "CEF-2.0"\n')...
    sprintf('END_OF_RECORD_MARKER = "$"\n')...
    sprintf('include = "C%d_CH_AUX_%s.ceh"\n', cl_id, datasetID)...
    sprintf(pmeta('FILE_TYPE','cef'))...
    sprintf(pmeta('DATASET_VERSION',DATASET_VERSION))...
    sprintf(pmeta('LOGICAL_FILE_ID',fileName))...
    sprintf(pmeta('VERSION_NUMBER',DATA_VERSION))...
    sprintf('START_META     =   FILE_TIME_SPAN\n')...
	sprintf('   VALUE_TYPE  =   ISO_TIME_RANGE\n')...
    sprintf('   ENTRY       =   %s/%s\n', ...
        epoch2iso(tint(1),1),epoch2iso(tint(2),1))...
    sprintf('END_META       =   FILE_TIME_SPAN\n')...
    sprintf('START_META     =   GENERATION_DATE\n')...
    sprintf('   VALUE_TYPE  =   ISO_TIME\n')...
    sprintf('   ENTRY       =   %s\n', epoch2iso(date2epoch(now()),1))...
    sprintf('END_META       =   GENERATION_DATE\n')...
    sprintf('!\n')...
    sprintf('!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n')...
    sprintf('!                       Data                          !\n')...
    sprintf('!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n')...
    sprintf('DATA_UNTIL = "END_OF_DATA"\n')];

%% Write the file
if 0
    % Write to plain CEF
    f = fopen([fileName '.cef'],'w'); %#ok<UNRCH>
    fwrite(f,header);
    fwrite(f,out_CharArray);
    fwrite(f,sprintf('END_OF_DATA\n'));
    fclose(f);
    return
else
    % Write directly GZIPed CEF file
    fileOutStream = java.io.FileOutputStream(java.io.File([fileName '.cef.gz']));
    gzipOutStream = java.util.zip.GZIPOutputStream( fileOutStream );
    gzipOutStream.write(java.lang.String(header).getBytes());
    gzipOutStream.write(java.lang.String(out_CharArray).getBytes());
    gzipOutStream.write(java.lang.String(sprintf('END_OF_DATA\n')).getBytes());
    gzipOutStream.close;
end
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function obuf = pmeta(metaID,metaValue)
% Print META
if isnumeric(metaValue), q = ''; metaValue = num2str(metaValue); else q = '"'; end
obuf = [...
    'START_META     =   ' metaID '\n'...
    '   ENTRY       =   ' q metaValue q '\n'...
    'END_META       =   ' metaID '\n'];
end