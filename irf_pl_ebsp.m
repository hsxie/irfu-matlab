function out = irf_pl_ebsp(ebsp,params)
%IRF_PL_EBSP  visualize EBSP 
%
%  H = IRF_PL_EBSP(EBSP,PARAMS)
%
%  Input:
%
%  EBSP is the output of IRF_EBSP()
%
%  PARAMS is cell array with a list of panels to plot: {PRAM, COMP, LIM_ARRAY}
%  where
%    PARAM     - one of the fields of EBSP
%    COMP      - component(s) of param, empty=plot all components
%    LIM_ARRAY - array of LIM_STRUCT used to limit the output. 
%
%  LIM_ARRAY has the following fields:
%    LIM_ARRAY.param - one of the fields of EBSP
%    LIM_ARRAY.comp  - component of LIM_ARRAY.param
%    LIM_ARRAY.val   - limiting value
%    LIM_ARRAY.type  - 'low' (data < LIM_ARRAY.val disregarded) or 'high'
%
%  Output:
%
%  H - handles to plots
%
%  Examples:
%
%  For a "MAARBLE type" plot:
%
%   limByDopStruct = struct('type','low','val',0.7,'param','dop','comp',1);
%   limByPlanarityStruct = struct('type','low','val',0.6,'param','planarity','comp',1);
%   limBSsumStruct = struct('type','low','val',.05,'param','bb_xxyyzzss','comp',4);
%   params = {{'bb_xxyyzzss',4,{limBSsumStruct}},...
%     {'ee_ss'},...
%     {'dop'},{'planarity'},...
%     {'ellipticity',[],{limByDopStruct,limByPlanarityStruct}},...
%     {'k_tp',[],{limByDopStruct,limByPlanarityStruct}},...
%     {'pf_rtp',1},...
%     {'pf_rtp',2,{limByDopStruct}}};
%
%  See also: IRF_EBSP

% ----------------------------------------------------------------------------
% "THE BEER-WARE LICENSE" (Revision 42):
% <yuri@irfu.se> wrote this file.  As long as you retain this notice you
% can do whatever you want with this stuff. If we meet some day, and you think
% this stuff is worth it, you can buy me a beer in return.   Yuri Khotyaintsev
% ----------------------------------------------------------------------------

%% Main function
% Default plot
if nargin==1 || isempty(params)
  limByDopStruct = struct('type','low','val',0.7,'param','dop','comp',1);
  limByPlanarityStruct = struct('type','low','val',0.6,'param','planarity','comp',1);
  %limBSsumStruct = struct('type','low','val',.05,'param','bb_xxyyzzss','comp',4);
  
  params = {{'bb_xxyyzzss',4},...
    {'ee_ss'},...
    {'dop'},{'planarity'},...
    {'ellipticity',[],{limByDopStruct,limByPlanarityStruct}},...
    {'k_tp',[],{limByDopStruct,limByPlanarityStruct}},...
    {'pf_rtp',1},...
    {'pf_rtp',2,{limByDopStruct}}};
end

fieldsEBSP = fields(ebsp);
IGNORE_FIELDS = {'t','f','fac','fullB','B0','r'};
fieldsPlottable = setxor(fieldsEBSP,IGNORE_FIELDS);
plotFields = ''; plotComps = ''; limFields = ''; nPanels = 0;
GetPlotParams();
    
h = irf_plot(nPanels);
sr = struct('t',ebsp.t,'f',ebsp.f);
for idxField = 1:length(plotFields)
  for idxComp = 1:length(plotComps{idxField})
    field = plotFields{idxField}; comp = plotComps{idxField}(idxComp);
    lim = limFields{idxField};
    [paramStr,compStr] = GetCompStrings();
    if isempty(compStr), panelStr = paramStr;
    else panelStr = [paramStr '_' compStr]; 
    end
    hca = irf_panel(panelStr);
    sr.p = UpdateUnits(ebsp.(field)(:,:,comp));
    sr.p = LimitValues(sr.p);
    [sr.plot_type,sr.p_label] = GetPlotTypeLabel();
    irf_spectrogram(hca,sr)
    set(hca,'YScale','log')
    SetCaxis()
  end
end
irf_zoom(h,'x',ebsp.t([1 end])')

if ~isempty(ebsp.r)
  xlabel(h(end),''), add_position(h(end),ebsp.r)
  title(h(1),irf_disp_iso_range(ebsp.t([1 end])',1))
end
if nargout, out = h; end % Return here

%% Help functions
  function GetPlotParams
    for idx = 1:length(params)
      p = params{idx};
      
      param = p{1};
      if ~ischar(param)
        error('invalid FIELD_NAME for parameter #%d, expecting string',idx)
      end
      if isempty(intersect({param},fieldsPlottable)), continue, end
      plotFields = [plotFields {param}]; %#ok<AGROW>
      
      if length(p)>1 && ~isempty(p{2})
        comps = p{2};
        if ~isnumeric(comps) || any(comps<0) || any( comps ~= uint8(comps))
          error('invalid COMP for parameter %s, expecting positive integer array',p{1})
        end
        nComps = length(comps);
      else
        nComps = size(ebsp.(p{1}),3);
        comps = 1:nComps;
      end
      plotComps = [plotComps {comps}]; %#ok<AGROW>
      
      if length(p)>2 && ~isempty(p{3})
        for idxLim = 1:length(p{3})
          s = ValidateLimStruct(p{3}{idxLim});
          if s, error('invalid LIM_STRUCT for parameter %s, %s',param, s), end
        end
        limFields = [limFields p(3)]; %#ok<AGROW>
      else
        limFields = [limFields {''}]; %#ok<AGROW>
      end
      
      nPanels = nPanels + nComps;
    end
    function s = ValidateLimStruct(limStruct)
      s= '';
      if ~isstruct(limStruct), s = 'expecting a structure'; return, end
      if any(~isfield(limStruct,{'type','val','param','comp'}))
        s = 'expecting a structure with fileds: type, val, param, comp';
        return
      end
      if ~ischar(limStruct.type) || ...
          isempty(intersect({lower(limStruct.type)},{'low','high'}))
        s = 'field TYPE must be ''low'' or ''high''';
        return
      end
      if ~isnumeric(limStruct.val)
        s = 'value of field VAL must be numeric'; return
      end
      if ~ischar(limStruct.param)
        s = 'field PARAM must be a string'; return
      end
      if isempty(intersect({limStruct.param},fieldsPlottable))
        s = ['invalid field PARAM: ''' limStruct.param ''' is not a member of EBSP'];
        return
      end
      if ~isnumeric(limStruct.comp) || length(limStruct.comp) > 1 || ...
          limStruct.comp < 0 || limStruct.comp ~= uint8(limStruct.comp)
        s = 'value of field COMP must be a positive integer'; return
      end
    end
  end
  function data = LimitValues(data)
    if isempty(lim), return, end
    for idx = 1:length(lim)
      limStruct = lim{idx};
      limData = ebsp.(limStruct.param)(:,:,limStruct.comp);
      switch lower(limStruct.type)
        case 'low'
          data(limData < limStruct.val) = NaN;
        case 'high'
          data(limData > limStruct.val) = NaN;
      end
    end
  end
  function [f,c] = GetCompStrings
    a = tokenize(field,'_');
    f = a{1}; c = '';
    if length(a) ==1, return, end 
    r = a{2};
    if length(unique(r)) == length(r), c = r(comp);
    else c = r((comp-1)*2+(1:2));
    end
    if strcmpi(c,'ss'), c = 'sum'; end
  end
  function [t,s] = GetPlotTypeLabel  
    t = 'lin';
    switch compStr
      case {'r','x','y','z','xx','yy','zz','sum'}
        s = ['log(' paramStr '_{' upper(compStr) '}) \newline ' GetUnits()];
        t = 'log';
      case 't'
        s = ['\Theta_{' paramStr '} [deg]'];
      case 'p'
        s = ['\Phi_{' paramStr '} [deg]'];
      otherwise
        s = paramStr;
    end
    function s = GetUnits
      switch paramStr
        case 'bb'
          s = '[nT^2/Hz';
        case 'ee'
          s = '[(mV/m)^2/Hz]';
        otherwise
          s = '[\mu W/m^2 Hz]^{1/2}';
      end
    end
  end
  function SetCaxis
    switch paramStr
      case {'dop','dop2d','planarity'}
        caxis(hca,[0 1])
      case 'ellipticity'
        caxis(hca,[-1 1])
      otherwise
        % do nothing
    end
    switch compStr
      case 't'
        caxis(hca,[0 180])
      case 'p'
        caxis(hca,[-180 180])
      otherwise
        % do nothing
    end
  end
  function a=UpdateUnits(a)
    switch compStr
      case {'t','p'}
        a = a*180/pi; % to degrees
    end
  end
end
    


