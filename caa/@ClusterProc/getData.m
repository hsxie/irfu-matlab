function data = getData(cp,cl_id,quantity,varargin)
%GETDATA(cp) produce Cluster level 2 and 3 data from the raw data
%
% data = getData(cp,cl_id,quantity,options)
%
% Input:
%	cp - ClusterProc object
%	cl_id - SC#
%	quantity - one of the following:
%
%	dies : diEs{cl_id}p12/32, diEs{cl_id}p34 -> mEDSI // spin fits [DSI]
%		also creates delta offsets D{cl_id}p12p34.
%		If the offset is real then it must be applied to p12/32,
%		if imaginary - to p34
%		has the following options:
%		sfit_ver - 0 (AIE c_efw_onesfit), 1 (BHN c_efw_c_efw_c_efw_spinfit_mx)
%		// default is to use the one specified in c_efw_sfit
%	die : diE{cl_id}p1234 -> mEDSI // despun full res E [DSI]
%		also created ADC offsets Da{cl_id}p12 and Da{cl_id}p34
%	idies, idie : idiEs{cl_id}p12, idiEs{cl_id}p34, idiE{cl_id}p1234 -> mEIDSI
%   Transform from SC to inertial frame
%	dieburst : dibE{cl_id}p1234 -> mEFWburst // despun ib(8kHz) E [DSI]
%		ADC offsets are NOT corrected
%	edbs,edb,iedb,iedbs : // Ez from E.B=0 [DSI+GSE]
%   E[s]{cl_id}, diE[s]{cl_id} -> mEdB    // SC frame
%   iE[s]{cl_id}, idiE[s]{cl_id} -> mEdBI  // Inertial frame
%		has the following options:
%		ang_limit - minimum angle(B,spin plane) [default 10 deg]
%		ang_blank - put Ez to NaN for points below ang_limit [default]
%		ang_fill - fill points below ang_limit with 1e27
%		ang_ez0 - use Ez=0 for points below ang_limit
%		probe_p - probe pair to use 12 or 34 [default 34]
%	P[s]{cl_id} -> mP	// P spin resolution
%	edi : EDI{cl_id}, diEDI{cl_id} -> mEDI // EDI E in sc ref frame
%	br, brs : Br[s]{cl_id}, diBr[s]{cl_id} -> mBr // B resampled to E[s]
%	vedbs, vedb : VExB[s]{cl_id}, diVExB[s]{cl_id} -> mEdB // E.B=0 [DSI+GSE]
%
% Example: 
%		getData(cp,4,'edbs','ang_fill','ang_limit',20,'probe_p',12)
%
%	General options - one of the following:
%		nosave : do no save on disk
%		withwhip : do not remove time intervals with Whisper pulses
%		notusesavedoff : recalculating everything instead of using saved offsets
%
% See also C_GET, C_CTL
%
% $Id$

% Copyright 2004 Yuri Khotyaintsev
% Parts of the code are (c) Andris Vaivads

error(nargchk(3,15,nargin))
if nargin > 3, have_options = 1; args = varargin;
else, have_options = 0;
end

% default options
flag_save = 1;
flag_usesavedoff = 0;
flag_edb = 1;
sfit_ver = -1;

flag_rmwhip = c_ctl(cl_id,'rm_whip');
if isempty(flag_rmwhip), flag_rmwhip = 1; end 
ang_limit = c_ctl(cl_id,'ang_lim');
if isempty(ang_limit), ang_limit = 10; end
probe_p = c_ctl(cl_id,'probe_p');
if isempty(probe_p), probe_p = 34; end
deltaof_max = c_ctl(cl_id, 'deltaof_max');
if isempty(deltaof_max), deltaof_max = 2; end
while have_options
	l = 1;
	switch(args{1})
	case 'nosave'
		flag_save = 0;
	case 'withwhip'
		flag_rmwhip = 0;
	case 'notusesavedoff'
		flag_usesavedoff = 0;
	case 'ang_limit'
		if length(args)>1
			if isnumeric(args{2})
				ang_limit = args{2};
				l = 2;
			else, irf_log('fcal,','wrongArgType : ang_limit must be numeric')
			end
		else, irf_log('fcal,','wrongArgType : ang_limit value is missing')
		end
	case 'ang_blank'
		flag_edb = 1;	% [default]
	case 'ang_fill'
		flag_edb = 2;	% fill points below ang_limit with 1e27
		fill_val = 1e27;
	case 'ang_ez0'
		flag_edb = 0;	% use Ez=0 for points below ang_limit
	case 'probe_p'
		if length(args)>1
			if isnumeric(args{2})
				probe_p_tmp = args{2};
				l = 2;
			else, probe_p_tmp = str2num(args{2});
			end
			if (probe_p_tmp==12 | probe_p_tmp==34), probe_p = probe_p_tmp;
			else, irf_log('fcal,','wrongArgType : probe_p must be 12 or 34')
			end
		else, irf_log('fcal,','wrongArgType : ang_limit value is missing')
		end
	case 'sfit_ver'
		if length(args)>1
			if isnumeric(args{2})
				l = 2;
				if	args{2}>=0 & args{2}<2
					sfit_ver = args{2};
				else, irf_log('fcal,','wrongArgType : sfit_ver must be 0 or 1')
				end
			else, irf_log('fcal,','wrongArgType : sfit_ver must be numeric')
			end
		else, irf_log('fcal,','wrongArgType : sfit_ver value is missing')
		end
	otherwise
		irf_log('fcal,',['Option ''' args{i} '''not recognized'])
	end
	if length(args) > l, args = args(l+1:end);
	else break
	end
end


save_file = '';
save_list = '';

old_pwd = pwd;
cd(cp.sp) %enter the storage directory
if cp.sp~='.', irf_log('save',['Storage directory is ' cp.sp]), end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% dies - spin fiting of Electric field
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
if strcmp(quantity,'dies')
	save_file = './mEDSI.mat';
	
	if ~c_load('A?',cl_id)
		irf_log('load',...
			irf_ssub('No A? in mA. Use getData(CDB,...,cl_id,''a'')',cl_id))
	end
	if ~(c_load('wE?p12',cl_id) | c_load('wE?p32',cl_id) | c_load('wE?p34',cl_id)) 
		irf_log('load',...
			irf_ssub(['No wE?p12/32 and/or wE?p34 in mER. Use getData(CDB,...,cl_id,''e'')'],cl_id))
		data = []; cd(old_pwd); return
	end

	p12 = 12;
	pl=[12,32,34];
	for k=1:length(pl)
		ps = num2str(pl(k));
		if exist(irf_ssub(['wE?p' ps],cl_id),'var')
			if pl(k)==32, p12 = 32; end
			c_eval(['tt=wE?p' ps ';aa=A?;'],cl_id)
			irf_log('proc',sprintf('Spin fit wE%dp%d -> diEs%dp%d',cl_id,pl(k),cl_id,pl(k)))

			if flag_rmwhip
				if exist('./mFDM.mat','file')
					c_eval('load mFDM WHIP?',cl_id)
				end
				if exist(irf_ssub('WHIP?',cl_id),'var')
					irf_log('proc','not using times with Whisper pulses')
					c_eval('tt=caa_rm_blankt(tt,WHIP? );clear WHIP?',cl_id)
				end
			end
			
			if sfit_ver>=0
				irf_log('proc',['using SFIT_VER=' num2str(sfit_ver)])
				sp = c_efw_sfit(pl(k),3,10,20,tt(:,1),tt(:,2),aa(:,1),...
					aa(:,2),sfit_ver);
			else
				sp = c_efw_sfit(pl(k),3,10,20,tt(:,1),tt(:,2),aa(:,1),aa(:,2));
			end
			
			% remove point with zero time
			ind = find(sp(:,1)>0);
			if length(ind)<length(sp(:,1))
				irf_log('proc',[num2str(length(sp(:,1))-length(ind)) ' spins removed (bad time)']);
				sp = sp(ind,:);
			end
			
			adc_off = sp(:,[1 4]);
			% warn about points with sdev>.8
			ii = find(sp(:,6)>.8);
			if length(ii)/size(sp,1)>.05,
				irf_log('proc',[sprintf('%.1f',100*length(ii)/size(sp,1)) '% of spins have SDEV>.8 (ADC offsets)']);
			end
			%adc_off(ii,2) = 0;
			adc_off = irf_waverage(adc_off,1/4);
			ii = find(adc_off(:,2)==0);
			adc_off(ii,2) = mean(adc_off(find(abs(adc_off(:,2))>0),2));
			
			sp = sp(:,[1:4 6]);
			sp(:,4) = 0*sp(:,4); % Z component
			
			% remove spins with bad spin fit (obtained E > 10000 mV/m)
			ind = find(abs(sp(:,3))>1e4); sp(ind,:) = [];
			if ind, disp([num2str(length(ind)) ' spins removed due to E>10000 mV/m']);end
			eval(irf_ssub(['diEs?p' ps '=sp;Dadc?p' ps '=adc_off;'],cl_id)); 
			clear tt aa sp adc_off
			eval(irf_ssub(['save_list=[save_list ''diEs?p' ps ' Dadc?p' ps ' ''];'],cl_id));
		else
			irf_log('load',sprintf('No p%d data for sc%d',pl(k),cl_id))
		end
	end

	% Delta offsets
	if (exist(irf_ssub('diEs?p12',cl_id),'var') | ...
	exist(irf_ssub('diEs?p32',cl_id),'var')) & exist(irf_ssub('diEs?p34',cl_id),'var')
		
		% To compute delta offsets we remove points which are > deltaof_max*sdev
		% as this must de a stable quantity
		eval(irf_ssub(['df=diEs?p!(:,2:3)-diEs?p34(:,2:3);'],cl_id,p12))
		sdev = std(df);
		comp_s = 'xy';
		for comp = 1:2
			ii = find(abs(df(:,comp)-mean(df(:,comp))) > deltaof_max*sdev(comp)); 
			irf_log('calb',sprintf('%d points are removed for delta_%s',...
				length(ii),comp_s(comp)))
			ddd = df(:,comp); ddd(ii) = [];
			Del(comp) = mean(ddd);
		end
		
		irf_log('calb',sprintf('delta offsets are: %.2f [x] %.2f [y]', ...
			abs(Del(1)), abs(Del(2))))

		% We suppose that smaller field is more realistic
		% and will correct the largest signal.
		% If we have p32, we always correct it, not p34.
		% Real offset is applied to p12, imaginary to p34.
		if Del(1)>0 & p12==12, Del = -Del*j; end
		eval(irf_ssub('D?p12p34=Del;',cl_id))

		if real(Del)
			irf_log('calb',irf_ssub('correcting p?',p12))
			eval(irf_ssub('diEs?p!(:,2:3)=diEs?p!(:,2:3)-ones(size(diEs?p!,1),1)*Del;',cl_id,p12));
		else
			irf_log('calb','correcting p34')
			Del = imag(Del);
			c_eval('diEs?p34(:,2:3)=diEs?p34(:,2:3)-ones(size(diEs?p34,1),1)*Del;',cl_id);
		end
		clear m12 m34 Del

		eval(irf_ssub(['save_list=[save_list ''D?p12p34 ''];'],cl_id));
	end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% die - despin of full resolution data.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
elseif strcmp(quantity,'die') | strcmp(quantity,'dieburst')
	if strcmp(quantity,'dieburst'), do_burst = 1; else do_burst = 0; end
	if do_burst
		save_file = './mEFWburst.mat';
                var_name = 'wbE?p';
		var1_name = 'dibE?p1234';
	else
		save_file = './mEDSI.mat';
                var_name = 'wE?p';
		var1_name = 'diE?p1234';
	end

	if ~c_load('A?',cl_id)
		irf_log('load',...
			irf_ssub('No A? in mA. Use getData(CDB,...,cl_id,''a'')',cl_id))
	end
	if ~exist('./mEDSI.mat','file')
		irf_log('load','Please compute spin averages (mEDSI)')
		data = []; cd(old_pwd); return
	end
	if do_burst, c_eval(['load mEFWburst ' var_name '12 ' var_name '34;'],cl_id);
	else, c_eval(['load mER ' var_name '12 ' var_name '32 ' var_name '34;'],cl_id);
	end
	
	% calibration coefficients // see c_efw_despin
	coef=[[1 0 0];[1 0 0]];

	pl=[12,32,34];
	full_e = [];
	n_sig = 0;
	p12 = 12;
	
	for k=1:length(pl)
		ps = num2str(pl(k));
		if exist(irf_ssub([var_name ps],cl_id),'var')
			if pl(k)==32, p12 = 32; end
			n_sig = n_sig + 1;
			if do_burst
				c_eval(['Ep' ps '=' var_name ps ';'],cl_id);
				% correct ADC offset
				if exist('./mEDSI.mat','file')
					eval(irf_ssub(['load mEDSI Da?p' ps ' Dadc?p' ps],cl_id))
				end
				if exist(irf_ssub(['Dadc?p' ps],cl_id),'var')
					c_eval(['irf_log(''calb'',''using saved Dadc?p' ps ''')'],cl_id)
					c_eval(['tmp_adc = irf_resamp(Dadc?p' ps ',Ep' ps ');'],cl_id)
					c_eval(['Ep' ps '(:,2)=Ep' ps '(:,2)-tmp_adc(:,2);'],cl_id)
					clear tmp_adc
				elseif exist(irf_ssub(['Da?p' ps],cl_id),'var')
					c_eval(['irf_log(''calb'',sprintf(''Da?dp' ps ' (using saved) : %.2f'',Da?p' ps '))'],cl_id)
					c_eval(['Ep' ps '(:,2)=Ep' ps '(:,2)-Da?p' ps ';'],cl_id)
				else
					irf_log('calb','ADC offset not corrected')
				end
			else
				% correct ADC offset
				if flag_usesavedoff & exist('./mEDSI.mat','file')
					eval(irf_ssub(['load mEDSI Da?p' ps ' Dadc?p' ps],cl_id))
				end
				if exist(irf_ssub(['Dadc?p' ps],cl_id),'var')
					c_eval(['irf_log(''calb'',''using saved Dadc?p' ps ''')'],cl_id)
					c_eval(['Ep' ps '=wE?p' ps '; tmp_adc = irf_resamp(Dadc?p' ps ',Ep' ps ');'],cl_id)
					c_eval(['Ep' ps '(:,2)=Ep' ps '(:,2)-tmp_adc(:,2);'],cl_id)
					clear tmp_adc
				elseif exist(irf_ssub(['Da?p' ps],cl_id),'var')
					c_eval(['disp(sprintf(''Da?dp' ps ' (using saved) : %.2f'',Da?p' ps '))'],cl_id)
					c_eval(['Ep' ps '=wE?p' ps '; Ep' ps '(:,2)=Ep' ps '(:,2)-Da?p' ps ';'],cl_id)
				else
					if flag_rmwhip & exist('./mFDM.mat','file')
						c_eval('load mFDM WHIP?',cl_id)
					end
					if flag_rmwhip & exist(irf_ssub('WHIP?',cl_id),'var')
						%removing times with Whisper pulses
						c_eval(['[Ep' ps ',Da?p' ps ']=caa_corof_adc(wE?p' ps ',WHIP?);clear WHIP?'],cl_id)
					else
						c_eval(['[Ep' ps ',Da?p' ps ']=caa_corof_adc(wE?p' ps ');'],cl_id)
					end
					c_eval(['irf_log(''calb'',sprintf(''Da?dp' ps ' : %.2f'',Da?p' ps '))'],cl_id)
					c_eval(['save_list=[save_list '' Da?p' ps ' ''];'],cl_id);
				end
			end
		end
	end
	if n_sig==0
		irf_log('load','No raw data found in mER')
		data = []; cd(old_pwd); return
	end
	if n_sig==2
		if p12==32 
			Ep12 = Ep32; clear Ep32
			E_info.probe = '3234';
		else
			E_info.probe = '1234';
		end
		if abs(length(Ep12)-length(Ep34))>0
			% different timelines. Need to correct
			irf_log('proc','using common timeline')
			[ii12,ii34] = irf_find_comm_idx(Ep12,Ep34);
			irf_log('proc',['Ep' num2str(p12) ' ' num2str(length(Ep12)) '->' num2str(length(ii12)) ' data points'])
			Ep12 = Ep12(ii12,:);
			irf_log('proc',['Ep34 ' num2str(length(Ep34)) '->' num2str(length(ii34)) ' data points'])
			Ep34 = Ep34(ii34,:);
		end
		% use WEC coordinate system E=[t,0,p34,p12]
		full_e = zeros(length(Ep12),4);
		full_e(:,[1,4]) = Ep12;
		full_e(:,3) = Ep34(:,2);
		clear Ep12 Ep34
	else
		if exist('Ep12','var')
			pp = 12;
			E_info.probe = '12';
			EE = Ep12;
			clear Ep12
		else
			pp = 34;
			E_info.probe = '34';
			EE = Ep34;
			clear Ep34
		end
		% use WEC coordinate system E=[t,0,p34,p12]
		full_e = zeros(length(EE),4);
		full_e(:,1) = EE(:,1);
		if pp==12, full_e(:,4) = EE(:,2);
		else, full_e(:,3) = EE(:,2);
		end
		clear EE pp
	end

	if ~do_burst
		% load Delta offsets D?p12p34
		if exist('./mEDSI.mat','file')
			eval(irf_ssub('load mEDSI D?p12p34;',cl_id));
		end
		if exist(irf_ssub('D?p12p34',cl_id))
			eval(irf_ssub('Del=D?p12p34;',cl_id))
			if real(Del) % Real del means we must correct p12. real(Del)==imag(Del)
				irf_log('calb',['correcting p' num2str(p12)])
				i_c = 1;
			else
				irf_log('calb','correcting p34')
				Del = imag(Del);
				i_c = 2;
			end
			eval(irf_ssub('coef(i_c,3)=Del(1)-Del(2)*1j;',cl_id));
			clear Del
	
		else, irf_log('calb','no Delta offsets found in mEDSI, not doing correction...')
		end
		c_eval([var1_name '_info=E_info;save_list=[save_list ''' var1_name '_info ''];'],cl_id);
	end

	% Do actual despin
	if p12==32, c_eval([var1_name '=c_efw_despin(full_e,A?,coef,''asym'');'],cl_id);
	else, c_eval([var1_name '=c_efw_despin(full_e,A?,coef);'],cl_id);
	end
	% DS-> DSI
	c_eval([var1_name '(:,3)=-' var1_name '(:,3);'],cl_id);
	c_eval(['save_list=[save_list ''' var1_name '''];'],cl_id);
	
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% idie, idies - DSI inertial
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
elseif strcmp(quantity,'idie') | strcmp(quantity,'idies')
	save_file = './mEIDSI.mat';

	if strcmp(quantity,'idie')
		var_s = {'diE?p1234'}; e_opt = 'die';
		var_b = 'diBr?'; b_opt ='br';
	else
		e_opt = 'dies';
		var_s = {'diEs?p12', 'diEs?p34'};
		var_b = 'diBrs?'; b_opt ='brs';
	end
	
	% Load resampled B
	[ok,diB] = c_load(var_b,cl_id);
	if ~ok
		irf_log('load',...
			irf_ssub(['No ' var_b ' in mBr. Use getData(CP,cl_id,''' b_opt ''')'],cl_id))
		data = []; cd(old_pwd); return
	end
	
	[ok,diV] = c_load('diV?',cl_id);
	if ~ok
		irf_log('load',...
			irf_ssub(['No diV? in mR. Use getData(CDB,...,cl_id,''v'')'],cl_id))
		data = []; cd(old_pwd); return
	end
	
	evxb = irf_tappl(irf_cross(diB,irf_resamp(diV,diB)),'*1e-3*(-1)');
	
	err_s = '';
	for k=1:length(var_s)
		[ok,diE] = c_load(var_s{k},cl_id);
		if ~ok
			if isempty(err_s), err_s = var_s{k};
			else, err_s = [err_s ', ' var_s{k}];
			end
			continue 
		end

		enew = diE;
		% We take only X and Y components. Z must remain zero.
		enew(:,2:3) = diE(:,2:3) - evxb(:,2:3);
		
		c_eval(['i' var_s{k} '= enew; clear enew'],cl_id)
		save_list=[save_list 'i' irf_ssub(var_s{k},cl_id) ' '];
	end
	if ~isempty(err_s)
		irf_log('load',...
			irf_ssub(['No ' err_s ' in mEDSI. Use getData(CP,cl_id,''' e_opt ''')'],cl_id))
		data = []; cd(old_pwd); return
	end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% edb,edbs,iedb,iedbs - E.B=0 (sc,inertial)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
elseif strcmp(quantity,'edb') | strcmp(quantity,'edbs') | ...
	strcmp(quantity,'iedb') | strcmp(quantity,'iedbs')
	
	if strcmp(quantity,'iedb') | strcmp(quantity,'iedbs'), inert = 1; 
	else, inert = 0; 
	end
	
	if inert, save_file = './mEdBI.mat';
	else, save_file = './mEdB.mat';
	end
	
	if strcmp(quantity,'edb') | strcmp(quantity,'iedb')
		var_s = irf_ssub('diE?p1234',cl_id); e_opt = 'die';
		varo_s = irf_ssub('E?',cl_id);
		var_b = 'diBr?'; b_opt ='br';
	else
		e_opt = 'dies';
		switch probe_p
		case 12
			irf_log('proc','using p12')
			var_s = irf_ssub('diEs?p12',cl_id);
		case 34
			irf_log('proc','using p34')
			var_s = irf_ssub('diEs?p34',cl_id);
		otherwise
			error(['Invalid probe pair ' num2str(probe_p)])
		end
		varo_s = irf_ssub('Es?',cl_id);
		var_b = 'diBrs?'; b_opt ='brs';
	end
	
	% Load resampled B
	[ok,diB] = c_load(var_b,cl_id);
	if ~ok
		irf_log('load',...
			irf_ssub(['No ' var_b ' in mBr. Use getData(CP,cl_id,''' b_opt ''')'],cl_id))
		data = []; cd(old_pwd); return
	end

	% Load V if we need to do SC->Inertial transformation
	if inert
		[ok,diV] = c_load('diV?',cl_id);
		if ~ok
			irf_log('load',...
				irf_ssub(['No diV? in mR. Use getData(CDB,...,cl_id,''v'')'],cl_id))
			data = []; cd(old_pwd); return
		end
	end
	
	Dxy_s =  irf_ssub('Ddsi?',cl_id);
	Dx_s =  irf_ssub('real(Ddsi?)',cl_id);
	Dy_s =  irf_ssub('imag(Ddsi?)',cl_id);
	Da_s =  irf_ssub('Damp?',cl_id);

	eval(['load mEDSI ' var_s ' ' Dxy_s ' ' Da_s])
	if exist(var_s,'var'), eval(['diE=' var_s ';'])
	else
		irf_log('load',...
			irf_ssub(['No ' var_s ' in mEDSI. Use getData(CP,cl_id,''' e_opt ''')'],cl_id))
		data = []; cd(old_pwd); return
	end
	if exist(Dxy_s,'var'), eval(['Dx=real(' Dxy_s ');Dy=imag(' Dxy_s ');'])
	else, irf_log('calb','using Dx=1,Dy=0'), Dx = 1; Dy=0;
	end
	if exist(Da_s,'var'), eval(['Da=' Da_s ';'])
	else, disp('using Da=1'), Da = 1;
	end

	diE = caa_corof_dsi(diE,Dx,Dy,Da);

	irf_log('proc',['using angle limit of ' num2str(ang_limit) ' degrees'])
	[diE,angle]=irf_edb(diE,diB,ang_limit);
	diE(:,5) = angle; clear angle

	ii = find(abs(diE(:,5)) < ang_limit);
	if length(ii) > 1
		switch(flag_edb)
		case 0 % Ez=0, do nothing
			irf_log('proc','using Ez=0')
		case 1 % Remove points
			irf_log('proc','setting points < ang_limit to NaN')
			diE(ii,4) = diE(ii,4)*NaN;
		case 2 % Fill with fill_val
			irf_log('proc','setting points < ang_limit to 1e27')
			diE(ii,4) = ones(size(diE(ii,4)))*fill_val;
		end
	end

	% SC -> Inertial
	if inert
		evxb = irf_tappl(irf_cross(diB,irf_resamp(diV,diB)),'*1e-3*(-1)');
		diE(:,2:4) = diE(:,2:4) - evxb(:,2:4); clear evxb
		s = 'i';
	else, s = '';
	end
	
 	% DSI->GSE
	if c_load('SAX?',cl_id)
		c_eval([s varo_s '=c_gse2dsi(diE(:,1:4),SAX?,-1);' s varo_s '(:,5)=diE(:,5);save_list=[save_list ''' s varo_s ' ''];'],cl_id);
	else
		irf_log('load',irf_ssub('No SAX? in mEPH. Use getData(CDB,...,cl_id,''sax'')',cl_id))
	end

	eval([ s 'di' varo_s '=diE;']); clear diE
	eval(irf_ssub('ang_limit?=ang_limit;',cl_id)) 
	save_list=[save_list s 'di' varo_s ' ang_limit' num2str(cl_id) ' '];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% edi (sc)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
elseif strcmp(quantity,'edi')
	
	save_file = './mEDI.mat';
	
	var_s = 'iEDI?'; e_opt = 'edi';
	varo_s = 'EDI?';
	
	% Load BPP. We use BPP for EDI as it must be a rather approximation
	[ok,B] = c_load('BPP?',cl_id);
	if ~ok
		[ok,B] = c_load('B?',cl_id);
		if ~ok
			irf_log('load',...
				irf_ssub(['No B? and BPP?. Use getData(CDB,...,cl_id,''b'')'],cl_id))
			data = []; cd(old_pwd); return
		end
	end

	% Load V if we need to do SC->Inertial transformation
	[ok,V] = c_load('V?',cl_id);
	if ~ok
		irf_log('load',...
			irf_ssub(['No diV? in mR. Use getData(CDB,...,cl_id,''v'')'],cl_id))
		data = []; cd(old_pwd); return
	end

	% Load E EDI (inertial)
	[ok,E] = c_load(var_s,cl_id);
	if ~ok
		irf_log('load',...
			irf_ssub(['No ' var_s ' in mEDI. Use getData(CP,cl_id,''' e_opt ''')'],cl_id))
		data = []; cd(old_pwd); return
	end

	% SC -> Inertial
	B = irf_resamp(B,E);
	evxb = irf_tappl(irf_cross(B,irf_resamp(V,B)),'*1e-3*(-1)');
	E(:,2:4) = E(:,2:4) + evxb(:,2:4); clear evxb
	
 	% GSE->DSI
	if c_load('SAX?',cl_id)
		c_eval(['di' varo_s '=c_gse2dsi(E(:,1:4),SAX?);save_list=[save_list '' di' varo_s ' ''];'],cl_id);
	else
		irf_log('load',irf_ssub('No SAX? in mEPH. Use getData(CDB,...,cl_id,''sax'')',cl_id))
	end

	c_eval([varo_s '= E;'],cl_id); clear E
	save_list=[save_list irf_ssub(varo_s,cl_id) ' '];

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Vedb,Vedbs = ExB with E.B=0
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
elseif strcmp(quantity,'vedb') | strcmp(quantity,'vedbs')
	save_file = './mEdB.mat';

	if strcmp(quantity,'vedb')
		var_s = 'diE?'; e_opt = 'edb';
		varo_s = 'VExB?';
		var_b = 'diBr?'; b_opt ='br';
	else
		var_s = 'diEs?'; e_opt = 'edbs';
		varo_s = 'VExBs?';
		var_b = 'diBrs?'; b_opt ='brs';
	end
	
	% Load resampled B
	[ok,diB] = c_load(var_b,cl_id);
	if ~ok
		irf_log('load',...
			irf_ssub(['No ' var_b ' in mBr. Use getData(CP,cl_id,''' b_opt ''')'],cl_id))
		data = []; cd(old_pwd); return
	end
	
	% Load data and calculate ExB
	if c_load(var_s,cl_id)
		c_eval(['di' varo_s '=irf_e_vxb(' var_s '(:,1:4),diB,-1);di' varo_s '(:,5)=' var_s '(:,5);'],cl_id)
	else
		irf_log('load',...
			irf_ssub(['No ' var_s ' in mEdB. Use getData(CP,cl_id,''' e_opt ''')'],cl_id))
		data = []; cd(old_pwd); return
	end

	save_list=[save_list 'di' irf_ssub(varo_s,cl_id) ' '];

	% DSI->GSE
	if c_load('SAX?',cl_id)
		eval(irf_ssub([varo_s '=c_gse2dsi(di' varo_s '(:,1:4),SAX?,-1);' varo_s '(:,5)=di' varo_s '(:,5);save_list=[save_list ''' varo_s ' ''];'],cl_id));
	else
		irf_log('load',irf_ssub('No SAX? in mEPH. Use getData(CDB,...,cl_id,''sax'')',cl_id))
	end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% B resampled to E and Es
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
elseif strcmp(quantity,'br') | strcmp(quantity,'brs')
	save_file = './mBr.mat';
	
	if strcmp(quantity,'br')
		var_b = 'Br?';
		[ok,E_tmp] = c_load('diE?p1234',cl_id);
		if ~ok
			irf_log('load',sprintf('Canot load diE%dp1234. Please load it.',cl_id))
			data = []; cd(old_pwd); return
		end
	else
		var_b = 'Brs?'; var_e = {'diEs?p34', 'diEs?p12'};
		[ok,E_tmp] = c_load(var_e{1},cl_id);
		if ~ok
			[ok,E_tmp] = c_load(var_e{2},cl_id);
			if ~ok
				irf_log('load',sprintf('Canot load diEs%d(p12|p34). Please load it.',cl_id))
				data = []; cd(old_pwd); return
			end
		end
	end
	
	% Load B GSE, as it is level 0 FGM data for us. 
	B_tmp = c_load('B?',cl_id,'var');
	
	% Check for data coverage
	% In the current approach we compute it from the sampling frequency of B.
	dt = E_tmp(end,1) - E_tmp(1,1);
	if ~isempty(B_tmp)
		Binfo = 'FR';
		bad_coverage = 0;
		cover = 0;
		B_tmp = irf_tlim(B_tmp,E_tmp(1,1) + [0 dt]);
		if isempty(B_tmp), bad_coverage = 1;
		else
			fgm_sf = 1/(B_tmp(2,1)-B_tmp(1,1));
			del_f = 1.5;
			if (fgm_sf > 22.5 - del_f) & (fgm_sf < 22.5 + del_f), fgm_sf = 22.5;
			elseif (fgm_sf > 67.5 - del_f) & (fgm_sf < 67.5 + del_f), fgm_sf = 67.5;
			else, irf_log('proc','cannot guess sampling frequency for B')
			end
			cover = length(B_tmp(:,1))/(dt*fgm_sf);
			% We allow for 10% of data gaps. (should we??)
			if cover < .9, bad_coverage = 1; end
		end
	else, bad_coverage = 1; cover = 0;
	end
	
	% Try to use BPP as a backup
	if bad_coverage
		BPP_tmp = c_load('BPP?',cl_id,'var');
		if isempty(BPP_tmp)
			% Use FR data if there is any (cover != 0)
			if cover==0
				irf_log('load','Canot load B. Please load B FGM or B PP.')
				data = []; cd(old_pwd); return
			end
		else
			BPP_tmp = irf_tlim(BPP_tmp,E_tmp(1,1) + [0 dt]);
			if isempty(BPP_tmp)
				irf_log('load','Canot find any usefull B data. Please load B FGM or B PP.')
				data = []; cd(old_pwd); return
			end
	
			fgm_sf = 1/(BPP_tmp(2,1)-BPP_tmp(1,1));
			del_f = .1;
			if (fgm_sf > .25 - del_f) & (fgm_sf < .25 + del_f), fgm_sf = .25;
			else, irf_log('proc','cannot guess sampling frequency for B PP')
			end
			cover_pp = length(BPP_tmp(:,1))/(dt*fgm_sf);
			
			% If there is more PP data, then use it.
			% Take .99 to avoid marginal effects.
			if .99*cover_pp > cover
				B_tmp = BPP_tmp;
				Binfo = 'PP';
				irf_log('proc','Using B PP to calculate Br')
			else, irf_log('proc',sprintf('Use B has %2.2f%% coverage',cover*100))
			end
		end
	end
	
	% Resample the data
	Br = irf_resamp(B_tmp,E_tmp);
	c_eval([ var_b '=Br;' var_b '_info=Binfo;save_list=[save_list ''' var_b ' '' '' ' var_b '_info '' ];'],cl_id)
	
	% DSI->GSE
	if c_load('SAX?',cl_id)
		eval(irf_ssub(['di' var_b '=c_gse2dsi(Br,SAX?); di' var_b '_info=Binfo;save_list=[save_list ''di' var_b ' '' '' di' var_b '_info '' ];'],cl_id));
	else
		irf_log('load',irf_ssub('No SAX? in mEPH. Use getData(CDB,...,cl_id,''sax'')',cl_id))
	end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% P resampled
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
elseif strcmp(quantity,'ps')
	save_file = './mP.mat';
	
	[ok,P_tmp] = c_load('P?',cl_id);
	if ~ok
		irf_log('load',sprintf('No P? in mP. Use getData(CDB,...,cl_id,''p'')',cl_id))
		data = []; cd(old_pwd); return
	end
	
	t0 = '';
	% Try to use time from spin fit
	% TODO: This code can be made smarter.
	[ok,Es_tmp] = c_load('diEs?p34',cl_id);
	if ok
		ii = find(abs(Es_tmp(:,1)-P_tmp(1,1))<2.1);
		if ~isempty(ii)
			irf_log('proc',irf_ssub('using timeline of diEs?p34',cl_id))
			t0 = Es_tmp(ii,1);
		end
	end
	clear Es_tmp
	
	if isempty(t0)
		irf_log('proc','using new timeline')
		t0 = P_tmp(1,1) + 2; 
	end
	
	n = floor((P_tmp(end,1)-t0)/4) + 1;
	tvec = t0 + ( (1:n) -1)*4;
	
	P_tmp = irf_resamp(P_tmp,tvec'); clear tvec
	c_eval('Ps?=P_tmp;save_list=[save_list ''Ps? '' ];',cl_id);
	
	[ok,P_info] = c_load('P?_info',cl_id);
	if ok
		c_eval('Ps?_info=P_info;save_list=[save_list ''Ps?_info '' ];',cl_id);
	end
	
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
else, error('caa:noSuchQuantity','Quantity ''%s'' unknown',quantity)
end %main QUANTITY
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% END OF DATA MANIPULATIONS
% saving
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% If flag_save is set, save variables to specified file
if flag_save==1 & length(save_file)>0 & ~isempty(save_list)
	irf_log('save',[save_list ' -> ' save_file])
	if exist(save_file,'file')
		eval(['save -append ' save_file ' ' save_list]);
	else
		eval(['save ' save_file ' ' save_list]);
	end
end

% prepare the output
if nargout > 0
	if isempty(save_list)
		data = [];
	else
		sl = tokenize(save_list);
		data = {sl};
		for k=1:length(sl)
			if exist(sl{k}), eval(['data{k+1}=' sl{k} ';']); end
		end
	end
end

cd(old_pwd)
