function [knl,ksn_master,bnd_list,Sc]=KsnProfiler(DEM,FD,A,S,varargin)
	% Function to interactively select channel heads and define segements over which to calculate channel steepness values.
	% 	This function is designed to be similar to the operation of Profiler_51, with some improvements. Function will display map
	%	with the stream network and expects the user to select a location near a channel head of interest. The user will be then 
	%	prompted to confirm that the defined stream is the desired choice. Finally, displays of the chi-z and longitudinal profile 
	%	of the selected river will appear and the user is expected to define (with mouse clicks) any obvious segments with different 
	%	channel steepness (or concavity) on either the chi-z plot or the stream profile (see 'pick_method' option). When done selecting 
	%	press enter/return. The user will be prompted whether they wish to continue picking streams or if they are done. When done 
	%	picking streams, the function will output three different products (see below) and produce a shapefile of the selected streams 
	%	with ksn, concavity, area, and gradient.
	%	
	% Required Inputs:
	%	DEM - Digital Elevation as a GRIDobj, assumes unconditioned DEM (e.g. DEMoc from ProcessRiverBasins or output from MakeStreams)
	%	FD - Flow direction as FLOWobj
	%	S - Stream network as STREAMobj
	%	A - Flow accumulation GRIDobj
	%
	% Optional Inputs:
	% 	input_method ['interactive'] - parameter which controls how streams of interest are supplied:
	%		'interactive' - user picks streams of interest by selecting channelheads on a map, this option will also iteratively build a 
	%			channel steepness map as the user picks more streams.
	%		'all_streams' - will use the supplied STREAMobj and iterate through all channel heads. There is an internal parameter to avoid 
	%			selecting streams that are too short to properly fit (mostly relevant if 'junction method' is set to 'check'). The default 
	%			value is ~4 * the DEM cellisze, the user can change this value by providing an input for the optional parameter 'min_channel_length',
	%			input should be in map units and greater than the default. You can use a code like 'SegmentPicker' to select portions of a STREAMobj
	%		'stream_length' - will use supplied STREAMobj and entry to 'min_length_to_extract' to iterate through all streams that are longer than
	%			the length provided to 'min_length_to_extract'. There is an internal parameter to avoid selecting streams that are too short to fit
	%			(mostly relevant if 'junction method' is set to 'check'). The default value is ~4 * the DEM cellsize, the user can change this value
	%			by providing an input for the optional parameter 'min_channel_length', input should be in map units and greater than the default.
	%		'channel_heads' - will use a supplied list of coordinates of channel heads to select and iterate through streams of interest. If this
	%			option is used, the user must provide an input for the optional 'channel_head_list' parameter.
	%	pick_method ['chi'] - choice of how you want to pick stream segments. The diagram within which to pick based on your selection will be 
	%			outline in red. Valid inputs are:
	%		'chi' - select segments on a chi - z plot (recommended and default)
	%		'stream' - select segments on a longitudinal profile
	%		'slope_area' - select segments on a slope area plot
	%	junction_method ['check'] - choice of how to deal with stream junctions:
	%		'check' - after each choice, will check whether downstream portions of the selected stream have already been fit, and if it has,
	%			the already fit portion of the stream will not be displayed or refit
	%		'ignore' - each stream will be displayed from its head to mouth independent of whether portions of the same stream network have 
	%			been fit
	%	concavity_method ['ref']- options for concavity:
	%		'ref' - uses a reference concavity, the user can specify this value with the reference concavity option (see below)
	%		'auto' - function finds a best fit concavity for each selected stream, if used in conjunction with 'junction_method','check'
	%			this means that short sections of streams picked will auto fit concavity that may differ from downstream portions of the same
	%			streams
	%	complete_networks_only [false] - if true, the code will filter out portions of the stream network that are incomplete prior to choosing
	%			streams
	%	ref_concavity [0.50] - refrence concavity used if 'theta_method' is set to 'ref'
	%	smooth_distance [1000] - distance in map units over which to smooth ksn measures when converting to shapefile
	%	display_slope_area [false] - logical flag to display slope area plots. Some people love slope area plots (like one of the authors of
	%			the supporting paper), some people hate slope area plots (like the other author of the supporting paper), so you can either 
	%			not draw them at all (false - default) or include them (true). This will automatically be set to true if you select 'slope_area'
	%			as the 'pick_method'.
	%	min_channel_length [] - minimum channel length for consideration when using the 'all_streams' method of input, provide in map units.
	%	channel_head_list [] - m x 2 array of x and y coordinates of channel heads, required when using 'channel_heads' method of input, 
	%			must be in the same coordinate system as the input DEM etc. The code will attempt to find the nearest channel head to the 
	%			coordinates you provided, so the closer the provided user coordinates are to channel heads, the more accurate this selection
	%			method will be.
	%	min_length_to_extract [] - minimum stream length (in map units) to extract streams if 'input_method' is set to 'stream_length'.
	%	min_elev [] - minimum elevation below which the code stops extracting channel information
	%	max_area [] - maximum drainage area above which the code stops extracting channel information (in square map units)
	%	plot_type ['vector'] - expects either 'vector' or 'grid', default is 'vector'. Controls whether all streams are drawn as individual 
	%			lines ('vector') or if the stream network is plotted as a grid and downsampled ('grid'). The 'grid' option is much faster on 
	%			large datasets, but can result in inaccurate channel head selection. The 'vector' option is easier to see, but can be very 
	%			slow to load and interact with on large datasets.	
	%	max_ksn [250] - maximum  ksn used for the color scale, will not effect actual results, for display purposes only
	%	threshold_area [1e6] - used to redraw downsampled stream network if 'plot_type' is set to 'downsample' 
	%	shape_name ['ksn'] - name for the shapefile to be export, must have no spaces to be a valid name for ArcGIS and should NOT include the '.shp'
	%	conditioned_DEM [] - option to provide a hydrologically conditioned DEM for use in this function (do not provide a conditoned DEM
	%			for the main required DEM input!) which will be used for extracting elevations. See 'ConditionDEM' function for options 
	%			for making a hydrological conditioned DEM. If no input is provided the code defaults to using the mincosthydrocon function.
	%	interp_value [0.1] - value (between 0 and 1) used for interpolation parameter in mincosthydrocon (not used if user provides a 
	%			conditioned DEM)
	%	save_figures [false] - logical flag to either save figures showing ksn fits (true) or to not (false - default)
	%		
	% Outputs:
	%	knl - n x 8 matrix of node list for selected stream segments, columns are x coordinate, y coordinate, drainage area, ksn,
	%		reference concavity, best fit concavity, gradient, and an identifying number. Note that if using the code in 'theta_method','auto' mode then the
	%		reference concavity and best fit concavity columns will be the same.
	%	ksn_master - identical to knl but as a cell array where individual cells are individual selected channels
	%	bnd_list - n x 4 matrix of selected bounds for fitting ksn, columns are x coordinate, y coordinate, elevation, and the stream identifying number 
	%		(this could be thought of as a list of knickpoints), also output as a seperate shapefile. If x y and z values appear as NaN, this indicates
	%		that bounds for this stream were not selected. 
	%	Sc - STREAMobj of selected streams
	%
	% Examples:
	%	[knl,ksn_master,bnd_list,Sc]=KSN_Profiler(DEM,FD,A,S);
	%	[knl,ksn_master,bnd_list,Sc]=KSN_Profiler(DEM,FD,A,S,'junction_method','ignore','ref_concavity',0.65,'max_ksn',500);
	%
	% Note:
	%	-If no boundaries/knickpoints are selected for any of the streams selected, then a '_knicks.shp' shapefile will not be produced.
	%
	%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
	% Function Written by Adam M. Forte - Last Revised Spring 2018 %
	%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

	% Parse Inputs
	p = inputParser;
	p.FunctionName = 'KsnProfiler';
	addRequired(p,'DEM',@(x) isa(x,'GRIDobj'));
	addRequired(p,'FD',@(x) isa(x,'FLOWobj'));
	addRequired(p,'A',@(x) isa(x,'GRIDobj'));
	addRequired(p,'S',@(x) isa(x,'STREAMobj'));

	addParamValue(p,'shape_name','ksn',@(x) ischar(x));
	addParamValue(p,'smooth_distance',1000,@(x) isscalar(x) && isnumeric(x));
	addParamValue(p,'concavity_method','ref',@(x) ischar(validatestring(x,{'ref','auto'})));
	addParamValue(p,'complete_networks_only',false,@(x) isscalar(x) && islogical(x));
	addParamValue(p,'pick_method','chi',@(x) ischar(validatestring(x,{'chi','stream','slope_area'})));
	addParamValue(p,'junction_method','check',@(x) ischar(validatestring(x,{'check','ignore'})));	
	addParamValue(p,'ref_concavity',0.50,@(x) isscalar(x) && isnumeric(x));
	addParamValue(p,'display_slope_area',false,@(x) isscalar(x) && islogical(x));
	addParamValue(p,'max_ksn',250,@(x) isscalar(x) && isnumeric(x));
	addParamValue(p,'min_elev',[],@(x) isscalar(x) && isnumeric(x));
	addParamValue(p,'max_area',[],@(x) isscalar(x) && isnumeric(x));
	addParamValue(p,'plot_type','vector',@(x) ischar(validatestring(x,{'vector','grid'})));
	addParamValue(p,'threshold_area',1e6,@(x) isnumeric(x));
	addParamValue(p,'input_method','interactive',@(x) ischar(validatestring(x,{'interactive','channel_heads','all_streams','stream_length'})));
	addParamValue(p,'channel_head_list',[],@(x) isnumeric(x) && size(x,2)==2);
	addParamValue(p,'min_length_to_extract',[],@(x) isnumeric(x) && isscalar(x));
	addParamValue(p,'min_channel_length',[],@(x) isnumeric(x) && isscalar(x));
	addParamValue(p,'conditioned_DEM',[],@(x) isa(x,'GRIDobj'));
	addParamValue(p,'interp_value',0.1,@(x) isnumeric(x) && x>=0 && x<=1);
	addParamValue(p,'save_figures',false,@(x) isscalar(x) && islogical(x));

	parse(p,DEM,FD,A,S,varargin{:});
	DEM=p.Results.DEM;
	FD=p.Results.FD;
	S=p.Results.S;
	A=p.Results.A;

	shape_name=p.Results.shape_name;
	smooth_distance=p.Results.smooth_distance;
	theta_method=p.Results.concavity_method;
	cno=p.Results.complete_networks_only;
	pick_method=p.Results.pick_method;
	junction_method=p.Results.junction_method;
	ref_theta=p.Results.ref_concavity;
	display_slope_area=p.Results.display_slope_area;
	plot_type=p.Results.plot_type;
	threshold_area=p.Results.threshold_area;
	input_method=p.Results.input_method;
	chl=p.Results.channel_head_list;
	mlte=p.Results.min_length_to_extract;
	min_channel_length=p.Results.min_channel_length;
	iv=p.Results.interp_value;
	DEMc=p.Results.conditioned_DEM;
	min_elev=p.Results.min_elev;
	max_area=p.Results.max_area;
	save_figures=p.Results.save_figures;

	% Max Ksn for color scaling
	mksn=p.Results.max_ksn;

    % Remove edges if flag is thrown
    if cno
    	S=removeedgeeffects(S,FD,DEM);
    end

	% Find channel heads
	[ch]=streampoi(S,'channelheads','xy');

	% Create master KSN colormap
	KSN_col=KsnColor(100);

	% Perform some checks and reassign values as needed
	if strcmp(input_method,'channel_heads')
		if isempty(chl)
			error('Selection method is "channel_heads", must provide an input for the "channel_head_list" parameter');
		end

		% Snap to nearest channel heads
		dists=pdist2(chl,ch);
		[~,s_ch_ix]=min(dists,[],2);
		s_ch=ch(s_ch_ix,:);
		num_ch=size(s_ch,1);

		plot_type='none';
		input_method='preselected';
	elseif strcmp(input_method,'all_streams')
		s_ch=ch;
		num_ch=size(s_ch,1);

		if isempty(min_channel_length);
			min_channel_length=sqrt((4*DEM.cellsize)^2 + (4*DEM.cellsize)^2);
		end

		plot_type='none';
		input_method='preselected';
	elseif strcmp(input_method,'stream_length')
		if isempty(mlte)
			error('Selection method is "stream_length", must provide an input for "mean_length_to_extract" parameter');
		end

		FlowD=flowdistance(FD);
		ix=coord2ind(DEM,ch(:,1),ch(:,2));
		idx=FlowD.Z(ix)>=mlte;

		s_ch=ch(idx,:);

		if isempty(s_ch)
			error('Input to "mean_length_to_extract" resulted in no streams being selected, reduce the length and retry')
		end

		num_ch=size(s_ch,1);

		if isempty(min_channel_length);
			min_channel_length=sqrt((4*DEM.cellsize)^2 + (4*DEM.cellsize)^2);
		end
		plot_type='none';
		input_method='preselected';
	end

	if strcmp(pick_method,'slope_area')
		display_slope_area=true;
	end

	if ~isempty(min_elev) && ~isempty(max_area)
		error('Providing values to both "min_elev" and "max_area" is not permitted, please only provide values for one of these parameters')
	end

	% Hydrologically condition dem
	if isempty(DEMc)
		zc=mincosthydrocon(S,DEM,'interp',iv);
		DEMc=GRIDobj(DEM);
		DEMc.Z(DEMc.Z==0)=NaN;
		DEMc.Z(S.IXgrid)=zc;
	end

	% Make gradient
	G=gradient8(DEMc);

	% Modify provided stream network if minimum elevation or maximum drainage area options are included
	if ~isempty(min_elev)
		zel=getnal(S,DEMc);
		idx=zel>min_elev;
		new_ix=S.IXgrid(idx);
		W=GRIDobj(DEMc,'logical');
		W.Z(new_ix)=true;
		S=STREAMobj(FD,W);
	elseif ~isempty(max_area)
		DA=A.*(A.cellsize^2);
		zda=getnal(S,DA);
		idx=zda<max_area;
		new_ix=S.IXgrid(idx);
		W=GRIDobj(DEMc,'logical');
		W.Z(new_ix)=true;
		S=STREAMobj(FD,W);		
	end

	% Generate Map Figures for interactive picking
	switch plot_type
	case 'grid'	

		disp('Downsampling datasets for display purposes')
		% Redo flow direction	
		DEMr=resample(DEM,DEM.cellsize*4);
		FDr=FLOWobj(DEMr,'preprocess','carve');
		% True outlets
		out_T_xy=streampoi(S,'outlets','xy');
		% Downsampled total stream network
		Sr_temp=STREAMobj(FDr,'minarea',threshold_area,'unit','mapunits');
		out_D_xy=streampoi(Sr_temp,'outlets','xy');
		out_D_ix=streampoi(Sr_temp,'outlets','ix');
		% Find if outlet list is different
		dists=pdist2(out_T_xy,out_D_xy);
		[~,s_out_ix]=min(dists,[],2);
		out_D_ix=out_D_ix(s_out_ix);
		% Rebuild downsampled network
		Sr=STREAMobj(FDr,'minarea',threshold_area,'unit','mapunits','outlets',out_D_ix);
		% Turn it into a grid
		SG=STREAMobj2GRIDobj(Sr);

		% Initiate Map Figure
		close all

		f1=figure(1);
		set(f1,'Visible','off');
		hold on
		[RGB]=imageschs(DEMr,SG,'colormap','gray');
		[~,R]=GRIDobj2im(DEMr);
		imshow(flipud(RGB),R);
		axis xy
		colormap(KSN_col);
		caxis([0 mksn])
		c1=colorbar;
		ylabel(c1,'Channel Steepness')
		hold off
		set(f1,'Visible','on','Units','normalized','Position',[0.05 0.1 0.5 0.5],'renderer','painters');

	case 'vector'

		% Initiate Map Figure
		close all

		f1=figure(1);
		set(f1,'Visible','off');

		[RGB]=imageschs(DEM,DEM,'colormap','gray');
		[~,R]=GRIDobj2im(DEM);

		imshow(flipud(RGB),R);
		axis xy
		hold on
		colormap(KSN_col);
		plot(S,'-w');
		caxis([0 mksn])
		c1=colorbar;
		ylabel(c1,'Channel Steepness')
		hold off
		set(f1,'Visible','on','Units','normalized','Position',[0.05 0.1 0.5 0.5],'renderer','painters');	
	end


	%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
	%% Main switch for graphical selection vs list of channel heads %%
	%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

	switch input_method
	case 'interactive'
		% Initiate counters and while loop values
		str1='N';
		str2='Y';
		ii=1;

		if strcmp(theta_method,'ref')
			% Autocalculate ksn for comparison purposes
			[auto_ksn]=KSN_Quick(DEM,A,S,ref_theta);
		end

		% Begin picking streams
		while strcmpi(str2,'Y');
			% Select channel to fit
			while strcmpi(str1,'N');	
				str3='R'; %Reset redo flag
	            disp('Zoom or pan to area of interest and then press enter');
	            pause();

				disp('    Choose point near channel head of interest')
				[x,y]=ginput(1);
				pOI=[x y];

				% Find nearest channel head
				distance=sqrt(sum(bsxfun(@minus, ch, pOI).^2,2));
				chOI=ch(distance==min(distance),:);

				% Build logical raster
				ix=coord2ind(DEM,chOI(:,1),chOI(:,2));
				IX=GRIDobj(DEM,'logical');
				IX.Z(ix)=true;

				% Extract stream of interest
				Sn=modify(S,'downstreamto',IX);

				% Build composite stream network of picked streams
				if strcmp(junction_method,'check')
					if ii>1
						[IIXX,~,~,Si]=intersectlocs(Sc,Sn);
						if isempty(IIXX)
							Sn=Sn;
							Sct=union(Sn,Sc,FD);
						else
							Sn=Si;
							Sct=union(Sn,Sc,FD);
						end
					else
						Sct=Sn;
					end
				elseif strcmp(junction_method,'ignore')					
					if ii>1
						Sct=union(Sn,Sc,FD);
					else
						Sct=Sn;
					end
				end

				figure(f1)
				hold on
				p1=plot(Sn,'-b','LineWidth',2);
				hold off

				prompt='    Is this the stream segment you wanted? Y/N [Y]: ';
				str1=input(prompt,'s');
				if isempty(str1)
					str1 = 'Y';
					Sc=Sct;
				elseif strcmpi(str1,'Y'); 
					Sc=Sct;
				else
					delete(p1);
				end
			end % End single channel select

			%% Calculate chi and extract ksn data
			if strcmp(theta_method,'ref')
				C=ChiCalc(Sn,DEMc,A,1,ref_theta);
				ak=getnal(Sn,auto_ksn);
			elseif strcmp(theta_method,'auto')
				C=ChiCalc(Sn,DEMc,A,1);
				[auto_ksn]=KSN_Quick(DEM,A,S,C.mn);
				ak=getnal(Sn,auto_ksn);
			end

			%% Bin data
			[DAvg,KsnAvg]=BinAverage(Sn.distance,ak,smooth_distance);
			[~,CAvg]=BinAverage(C.distance,C.chi,smooth_distance);

			%% Begin fitting loop
			while strcmpi(str3,'R')
				%% Initiate figure to pick bounds
				f2=figure(2);
				set(f2,'Units','normalized','Position',[0.5 0.1 0.45 0.8],'renderer','painters');
				clf	

				%% Main swith for different pick methods
				if strcmp(pick_method,'chi')

					if display_slope_area
						[bs,ba,bc,bd]=sa(DEMc,Sn,A,C.chi,smooth_distance);

						ax4=subplot(4,1,4);
						hold on
						scatter(ba,bs,20,bc,'filled','MarkerEdgeColor','k');
						xlabel('Log Area');
						ylabel('Log Gradient');
						title('Slope-Area');
						set(ax4,'YScale','log','XScale','log','XDir','reverse');
						hold off

						ax3=subplot(4,1,3);
						hold on
						plotdz(Sn,DEM,'dunit','km','Color',[0.5 0.5 0.5]);
						plotdz(Sn,DEMc,'dunit','km','Color','k');
						scatter((C.distance)./1000,C.elev,5,C.chi,'filled');
						xlabel('Distance from Mouth (km)')
						ylabel('Elevation (m)')
						legend('Unconditioned DEM','Conditioned DEM','Chi','location','best');
						title('Long Profile')
						hold off

						ax2=subplot(4,1,2);
						hold on
						scatter(CAvg,KsnAvg,20,CAvg,'filled','MarkerEdgeColor','k');
						xlabel('Chi')
						ylabel('Auto k_{sn}');
						title('Chi - Auto k_{sn}');
						hold off

						ax1=subplot(4,1,1);
						hold on
						plot(C.chi,C.elev,'-k');
						scatter(C.chi,C.elev,10,C.chi,'filled');
						xlabel('Chi')
						ylabel('Elevation (m)')
						title(['Chi - Z : \theta = ' num2str(C.mn) ' : Pick Segments'],'Color','r')
						ax1.XColor='Red';
						ax1.YColor='Red';
						hold off

						linkaxes([ax1,ax2],'x');
						colormap(ax1,'jet'); colormap(ax2,'jet'); colormap(ax3,'jet'); colormap(ax4,'jet');

					else
						ax3=subplot(3,1,3);
						hold on
						plotdz(Sn,DEM,'dunit','km','Color',[0.5 0.5 0.5]);
						plotdz(Sn,DEMc,'dunit','km','Color','k');
						scatter((C.distance)./1000,C.elev,5,C.chi,'filled')
						xlabel('Distance from Mouth (km)')
						ylabel('Elevation (m)')
						legend('Unconditioned DEM','Conditioned DEM','Chi','location','best');
						title('Long Profile')
						hold off

						ax2=subplot(3,1,2);
						hold on
						scatter(CAvg,KsnAvg,20,CAvg,'filled','MarkerEdgeColor','k');
						xlabel('Chi')
						ylabel('Auto k_{sn}');
						title('Chi - Auto k_{sn}');
						hold off

						ax1=subplot(3,1,1);
						hold on
						plot(C.chi,C.elev,'-k');
						scatter(C.chi,C.elev,10,C.chi,'filled');
						xlabel('Chi')
						ylabel('Elevation (m)')
						title(['Chi - Z : \theta = ' num2str(C.mn) ' : Pick Segments'],'Color','r')
						ax1.XColor='Red';
						ax1.YColor='Red';
						hold off

						linkaxes([ax1,ax2],'x');
						colormap(ax1,'jet'); colormap(ax2,'jet'); colormap(ax3,'jet');
					end	


					disp('    Select bounds for calculating channel steepnesses and press enter when completed')
					[cv,e]=ginput;

					if isempty(cv)
						if strcmp(theta_method,'ref')
							Cbf=ChiCalc(Sn,DEMc,A,1);
							ksn_list=[C.x C.y C.area ones(numel(C.x),1)*C.ks ones(numel(C.x),1)*C.ks_neg ones(numel(C.x),1)*C.ks_pos ...
								ones(numel(C.x),1)*C.mn ones(numel(C.x),1)*Cbf.mn];
						elseif strcmp(theta_method,'auto')
							ksn_list=[C.x C.y C.area ones(numel(C.x),1)*C.ks ones(numel(C.x),1)*C.ks_neg ones(numel(C.x),1)*C.ks_pos ...
								ones(numel(C.x),1)*C.mn ones(numel(C.x),1)*C.mn];
						end

						% Determine where ksn value fits into color scale and plot
						ksn_val=C.ks;

						if ksn_val > mksn;
							figure(f1)
							hold on
							plot(Sn,'Color',KSN_col(end,:),'LineWidth',2);
							hold off
						else
							edges=linspace(0,mksn,10);
							n=histc(ksn_val,edges);
							figure(f1)
							hold on
							plot(Sn,'Color',KSN_col(logical(n),:),'LineWidth',2);
							hold off	
						end

						[~,lbix]=min(C.chi);
						elbl=C.elev(lbix);

						if display_slope_area
							figure(f2)
							subplot(4,1,1);
							hold on
							plot(C.chi,C.pred+elbl,'-k','LineWidth',2);
							hold off

							subplot(4,1,3);
							hold on
							plot((C.distance)/1000,C.pred+elbl,'-k','LineWidth',2);
							hold off

							subplot(4,1,4);
							hold on
							plot(C.area,ksn_val.*C.area.^(-C.mn),'-k','LineWidth',2);
							hold off

						else
							figure(f2)
							subplot(3,1,1);
							hold on
							plot(C.chi,C.pred+elbl,'-k','LineWidth',2);
							hold off

							subplot(3,1,3);
							hold on
							plot((C.distance)/1000,C.pred+elbl,'-k','LineWidth',2);
							hold off
						end

						res_list=[C.chi C.res];
						bnd_ix=NaN;;

					else
						% Sort knickpoint list and construct bounds list
						cvs=sortrows(cv);
						bnds=vertcat(0,cvs,C.chi(1));

						num_bnds=numel(bnds);
						rc=C.chi;
						rx=C.x;
						ry=C.y;
						rd=C.distance;
						for jj=1:num_bnds-1
							% disp([' Calculating segment ' num2str(jj)])
							% Extract bounds
							lb=bnds(jj);
							rb=bnds(jj+1);

							% Clip out stream segment
							lb_chidist=sqrt(sum(bsxfun(@minus, rc, lb).^2,2));
							rb_chidist=sqrt(sum(bsxfun(@minus, rc, rb).^2,2));

							lbx=rx(lb_chidist==min(lb_chidist));
							lby=ry(lb_chidist==min(lb_chidist));

							rbx=rx(rb_chidist==min(rb_chidist));
							rby=ry(rb_chidist==min(rb_chidist));	

							lix=coord2ind(DEM,lbx,lby);
							LIX=GRIDobj(DEM,'logical');
							LIX.Z(lix)=true;	

							rix=coord2ind(DEM,rbx,rby);
							RIX=GRIDobj(DEM,'logical');
							RIX.Z(rix)=true;	

							Seg=modify(Sn,'downstreamto',RIX);
							Seg=modify(Seg,'upstreamto',LIX);

							% Construct bound list
							if jj<num_bnds-1
								bnd_ix(jj,1)=rix;
							end

							% Calculate chi to find ksn and bestfit concavity 
							if strcmp(theta_method,'ref')
								Cseg=ChiCalc(Seg,DEMc,A,1,ref_theta);
							elseif strcmp(theta_method,'auto')
								Cseg=ChiCalc(Seg,DEMc,A,1,C.mn);
							end
							Cbfseg=ChiCalc(Seg,DEMc,A,1);								

							% Determine where ksn value fits into color scale and plot
							ksn_val=Cseg.ks;

							if ksn_val > mksn;
								figure(f1)
								hold on
								plot(Seg,'Color',KSN_col(end,:),'LineWidth',2);
								hold off
							else
								edges=linspace(0,mksn,10);
								n=histc(ksn_val,edges);
								figure(f1)
								hold on
								plot(Seg,'Color',KSN_col(logical(n),:),'LineWidth',2);
								hold off	
							end

							ksn_nodes{jj,1}=[Cseg.x Cseg.y Cseg.area ones(numel(Cseg.x),1)*Cseg.ks ones(numel(Cseg.x),1)*Cseg.ks_neg ones(numel(Cseg.x),1)*Cseg.ks_pos ...
								ones(numel(Cseg.x),1)*Cseg.mn ones(numel(Cseg.x),1)*Cbfseg.mn];

							% Plot linear fits	
							rchi=rc(rb_chidist==min(rb_chidist));
							lchi=rc(lb_chidist==min(lb_chidist));
							segChi=linspace(lchi,rchi,numel(Cseg.chi));
							seg0Chi=linspace(0,max(Cseg.chi),numel(Cseg.chi));
							[~,lbix]=min(Cseg.chi);
							elbl=Cseg.elev(lbix);

							if display_slope_area
								figure(f2)
								subplot(4,1,1);
								hold on
								plot(segChi,(seg0Chi.*ksn_val)+elbl,'-k','LineWidth',2);
								hold off

								seg_st=rd(lb_chidist==min(lb_chidist));
								subplot(4,1,3);
								hold on
								plot((Cseg.distance+seg_st)/1000,(Cseg.pred)+elbl,'-k','LineWidth',2);
								hold off

								subplot(4,1,4);
								hold on
								plot(Cseg.area,ksn_val.*Cseg.area.^(-1*Cseg.mn),'-k','LineWidth',2);
								hold off
							else								
								figure(f2)
								subplot(3,1,1);
								hold on
								plot(segChi,(seg0Chi.*ksn_val)+elbl,'-k','LineWidth',2);
								hold off

								seg_st=rd(lb_chidist==min(lb_chidist));
								subplot(3,1,3);
								hold on
								plot((Cseg.distance+seg_st)/1000,(Cseg.pred)+elbl,'-k','LineWidth',2);
								hold off
							end

							res_list{jj,1}=[Cseg.chi+lchi Cseg.res];	

						end

						ksn_list=vertcat(ksn_nodes{:});
						res_list=vertcat(res_list{:});
					end

					%% Plot result figure
					if display_slope_area
						figure(f2)
						subplot(4,1,2)
						hold on
						plot(res_list(:,1),ksn_list(:,4),'-k','LineWidth',2);
						hold off
					else
						figure(f2)
						subplot(3,1,2)
						hold on
						plot(res_list(:,1),ksn_list(:,4),'-k','LineWidth',2);
						hold off
					end

					f3=figure(3);
					set(f3,'Units','normalized','Position',[0.05 0.1 0.45 0.8],'renderer','painters');

					clf
					subplot(2,1,2)
					hold on
					s1=scatter(CAvg,KsnAvg,20,'k','filled');
					p1=plot(res_list(:,1),ksn_list(:,4)-ksn_list(:,5),':k');
					plot(res_list(:,1),ksn_list(:,4)+ksn_list(:,6),':k');
					p2=plot(res_list(:,1),ksn_list(:,4),'-k','LineWidth',2);
					[ksn_vals,~,ksn_ix]=unique(ksn_list(:,4));
					chi_means=accumarray(ksn_ix,res_list(:,1),[],@nanmean);
					for kk=1:numel(ksn_vals)
						text(chi_means(kk),ksn_vals(kk),['k_{sn} = ' num2str(ksn_vals(kk))],...
							'VerticalAlignment','bottom','HorizontalAlignment','center');
					end
					xlabel('Chi')
					ylabel('k_{sn}')
					legend([s1 p1 p2],{'Auto k_{sn}','k_{sn} uncertainty','k_{sn} of fit segments'},'location','best');
					title('k_{sn} - Chi')
					hold off

					subplot(2,1,1)
					hold on
					plot([min(res_list(:,1)) max(res_list(:,1))],[0 0],'-k');
					scatter(res_list(:,1),res_list(:,2),10,'k','filled');
					xlabel('Chi')
					ylabel('Residual (m)')
					title('Residual on k_{sn} fit')
					hold off				


				elseif strcmp(pick_method,'stream')	

					if display_slope_area
						[bs,ba,bc,bd,bk]=sa_ksn(DEMc,Sn,A,C.chi,ak,smooth_distance);	

						ax4=subplot(4,1,4);
						hold on
						scatter(ba,bs,20,bd./1000,'filled','MarkerEdgeColor','k');
						xlabel('Log Area');
						ylabel('Log Gradient');
						title('Slope-Area');
						set(ax4,'XScale','log','YScale','log','XDir','reverse');
						hold off

						ax1=subplot(4,1,1);
						hold on
						plot(C.chi,C.elev,'Color',[0.5 0.5 0.5]);
						scatter(C.chi,C.elev,10,(C.distance)./1000,'filled');
						xlabel('Chi')
						ylabel('Elevation (m)')
						title(['Chi - Z : \theta = ' num2str(C.mn)])
						hold off

						ax2=subplot(4,1,2);
						hold on
						scatter(DAvg./1000,KsnAvg,20,DAvg./1000,'filled','MarkerEdgeColor','k');
						xlabel('Distance (km)')
						ylabel('Auto k_{sn}');
						title('Distance - Auto k_{sn}');
						hold off

						ax3=subplot(4,1,3);
						hold on
						plotdz(Sn,DEM,'dunit','km','Color',[0.5 0.5 0.5]);
						plotdz(Sn,DEMc,'dunit','km','Color','k');
						scatter((C.distance)./1000,C.elev,5,(C.distance)./1000,'filled');
						xlabel('Distance from Mouth (km)')
						ylabel('Elevation (m)')
						legend('Unconditioned DEM','Conditioned DEM','Stream Distance','location','best');
						title('Long Profile : Pick Segments','Color','r')
						ax3.XColor='Red';
						ax3.YColor='Red';
						hold off

						linkaxes([ax2,ax3],'x');
						colormap(ax1,'jet'); colormap(ax2,'jet'); colormap(ax3,'jet'); colormap(ax4,'jet')
					else
						ax1=subplot(3,1,1);
						hold on
						plot(C.chi,C.elev,'Color',[0.5 0.5 0.5]);
						scatter(C.chi,C.elev,10,(C.distance)./1000,'filled');
						xlabel('Chi')
						ylabel('Elevation (m)')
						title(['Chi - Z : \theta = ' num2str(C.mn)])
						hold off

						ax2=subplot(3,1,2);
						hold on
						scatter(DAvg./1000,KsnAvg,20,DAvg./1000,'filled','MarkerEdgeColor','k');
						xlabel('Distance (km)')
						ylabel('Auto k_{sn}');
						title('Distance - Auto k_{sn}');
						hold off

						ax3=subplot(3,1,3);
						hold on
						plotdz(Sn,DEM,'dunit','km','Color',[0.5 0.5 0.5]);
						plotdz(Sn,DEMc,'dunit','km','Color','k');
						scatter((C.distance)./1000,C.elev,5,(C.distance)./1000,'filled');
						xlabel('Distance from Mouth (km)')
						ylabel('Elevation (m)')
						legend('Unconditioned DEM','Conditioned DEM','Stream Distance','location','best');
						title('Long Profile : Pick Segments','Color','r')
						ax3.XColor='Red';
						ax3.YColor='Red';
						hold off

						linkaxes([ax2,ax3],'x');
						colormap(ax1,'jet'); colormap(ax2,'jet'); colormap(ax3,'jet');	
					end	

					disp('    Select bounds for calculating channel steepnesses and press enter when completed')
					[d,e]=ginput;
					d=d*1000; % convert back to meters;

					if isempty(d)
						if strcmp(theta_method,'ref')
							Cbf=ChiCalc(Sn,DEMc,A,1);
							ksn_list=[C.x C.y C.area ones(numel(C.x),1)*C.ks ones(numel(C.x),1)*C.ks_neg ones(numel(C.x),1)*C.ks_pos ...
								ones(numel(C.x),1)*C.mn ones(numel(C.x),1)*Cbf.mn];
						elseif strcmp(theta_method,'auto')
							ksn_list=[C.x C.y C.area ones(numel(C.x),1)*C.ks ones(numel(C.x),1)*C.ks_neg ones(numel(C.x),1)*C.ks_pos ...
								ones(numel(C.x),1)*C.mn ones(numel(C.x),1)*C.mn];
						end

						% Determine where ksn value fits into color scale and plot
						ksn_val=C.ks;

						if ksn_val > mksn;
							figure(f1)
							hold on
							plot(Sn,'Color',KSN_col(end,:),'LineWidth',2);
							hold off
						else
							edges=linspace(0,mksn,10);
							n=histc(ksn_val,edges);
							figure(f1)
							hold on
							plot(Sn,'Color',KSN_col(logical(n),:),'LineWidth',2);
							hold off	
						end

						[~,lbix]=min(C.chi);
						elbl=C.elev(lbix);
						if display_slope_area
							figure(f2)
							subplot(4,1,1);
							hold on
							plot(C.chi,C.pred+elbl,'-k','LineWidth',2);
							hold off

							subplot(4,1,3);
							hold on
							plot((C.distance)./1000,C.pred+elbl,'-k','LineWidth',2);
							hold off

							subplot(4,1,4);
							hold on
							plot(C.area,ksn_val.*C.area.^(-C.mn),'-k','LineWidth',2);
							hold off							
						else
							figure(f2)
							subplot(3,1,1);
							hold on
							plot(C.chi,C.pred+elbl,'-k','LineWidth',2);
							hold off

							subplot(3,1,3);
							hold on
							plot((C.distance)./1000,C.pred+elbl,'-k','LineWidth',2);
							hold off
						end

						res_list=[C.chi C.res];
						bnd_ix=NaN;;

					else
						% Sort knickpoint list and construct bounds list
						ds=sortrows(d);
						bnds=vertcat(0,ds,max(Sn.distance));

						num_bnds=numel(bnds);
						rd=C.distance; 
						rx=C.x;
						ry=C.y; 
						rc=C.chi;
						for jj=1:num_bnds-1
							% disp([' Calculating segment ' num2str(jj)])
							% Extract bounds
							lb=bnds(jj);
							rb=bnds(jj+1);

							% Clip out stream segment
							lb_dist=sqrt(sum(bsxfun(@minus, rd, lb).^2,2));
							rb_dist=sqrt(sum(bsxfun(@minus, rd, rb).^2,2));

							lbx=rx(lb_dist==min(lb_dist));
							lby=ry(lb_dist==min(lb_dist));

							rbx=rx(rb_dist==min(rb_dist));
							rby=ry(rb_dist==min(rb_dist));	

							lix=coord2ind(DEM,lbx,lby);
							LIX=GRIDobj(DEM,'logical');
							LIX.Z(lix)=true;	

							rix=coord2ind(DEM,rbx,rby);
							RIX=GRIDobj(DEM,'logical');
							RIX.Z(rix)=true;

							% Construct bound list
							if jj<num_bnds-1
								bnd_ix(jj,1)=rix;
							end	

							Seg=modify(Sn,'downstreamto',RIX);
							Seg=modify(Seg,'upstreamto',LIX);

							% Calculate chi to find ksn and bestfit concavity 
							if strcmp(theta_method,'ref')
								Cseg=ChiCalc(Seg,DEMc,A,1,ref_theta);
							elseif strcmp(theta_method,'auto')
								Cseg=ChiCalc(Seg,DEMc,A,1,C.mn);
							end
							Cbfseg=ChiCalc(Seg,DEMc,A,1);

							% Determine where ksn value fits into color scale and plot
							ksn_val=Cseg.ks;

							if ksn_val > mksn;
								figure(f1)
								hold on
								plot(Seg,'Color',KSN_col(end,:),'LineWidth',2);
								hold off
							else
								edges=linspace(0,mksn,10);
								n=histc(ksn_val,edges);
								figure(f1)
								hold on
								plot(Seg,'Color',KSN_col(logical(n),:),'LineWidth',2);
								hold off	
							end

							ksn_nodes{jj,1}=[Cseg.x Cseg.y Cseg.area ones(numel(Cseg.x),1)*Cseg.ks ones(numel(Cseg.x),1)*Cseg.ks_neg ones(numel(Cseg.x),1)*Cseg.ks_pos ...
								ones(numel(Cseg.x),1)*Cseg.mn ones(numel(Cseg.x),1)*Cbfseg.mn];

							% Plot linear fits	
							rchi=rc(rb_dist==min(rb_dist));
							lchi=rc(lb_dist==min(lb_dist));
							ld=rd(lb_dist==min(lb_dist));
							segChi=linspace(lchi,rchi,numel(Cseg.chi));
							seg0Chi=linspace(0,max(Cseg.chi),numel(Cseg.chi));
							[~,lbix]=min(Cseg.chi);
							elbl=Cseg.elev(lbix);
							if display_slope_area
								figure(f2)
								subplot(4,1,1);
								hold on
								plot(segChi,(seg0Chi.*ksn_val)+elbl,'-k','LineWidth',2);
								hold off

								seg_st=rd(lb_dist==min(lb_dist));
								subplot(4,1,3);
								hold on
								plot((Cseg.distance+seg_st)/1000,(Cseg.pred)+elbl,'-k','LineWidth',2);
								hold off

								subplot(4,1,4);
								hold on
								plot(Cseg.area,ksn_val.*Cseg.area.^(-Cseg.mn),'-k','LineWidth',2);
								hold off									
							else
								figure(f2)
								subplot(3,1,1);
								hold on
								plot(segChi,(seg0Chi.*ksn_val)+elbl,'-k','LineWidth',2);
								hold off

								seg_st=rd(lb_dist==min(lb_dist));
								subplot(3,1,3);
								hold on
								plot((Cseg.distance+seg_st)/1000,(Cseg.pred)+elbl,'-k','LineWidth',2);
								hold off	
							end						

							res_list{jj,1}=[Cseg.distance+ld Cseg.res];
						end

						ksn_list=vertcat(ksn_nodes{:});
						res_list=vertcat(res_list{:});
					end

					%% Plot fit result
					if display_slope_area
						figure(f2)
						subplot(4,1,2)
						hold on
						plot(res_list(:,1)./1000,ksn_list(:,4),'-k','LineWidth',2);
						hold off
					else
						figure(f2)
						subplot(3,1,2)
						hold on
						plot(res_list(:,1)./1000,ksn_list(:,4),'-k','LineWidth',2);
						hold off
					end

					f3=figure(3);
					set(f3,'Units','normalized','Position',[0.05 0.1 0.45 0.8],'renderer','painters');

					clf
					subplot(2,1,2)
					hold on
					s1=scatter(DAvg./1000,KsnAvg,20,'k','filled');
					p1=plot(res_list(:,1)./1000,ksn_list(:,4)-ksn_list(:,5),':k');
					plot(res_list(:,1)./1000,ksn_list(:,4)+ksn_list(:,6),':k');
					p2=plot(res_list(:,1)./1000,ksn_list(:,4),'-k','LineWidth',2);
					[ksn_vals,~,ksn_ix]=unique(ksn_list(:,4));
					d_means=accumarray(ksn_ix,res_list(:,1),[],@nanmean);
					for kk=1:numel(ksn_vals)
						text(d_means(kk)./1000,ksn_vals(kk),['k_{sn} = ' num2str(ksn_vals(kk))],...
							'VerticalAlignment','bottom','HorizontalAlignment','center');
					end
					xlabel('Distance (km)')
					ylabel('k_{sn}')
					title('k_{sn} - Distance')
					legend([s1 p1 p2],{'Auto k_{sn}','k_{sn} uncertainty','k_{sn} of fit segments'},'location','best');
					hold off

					subplot(2,1,1)
					hold on
					plot([min(res_list(:,1)./1000) max(res_list(:,1)./1000)],[0 0],'-k');
					scatter(res_list(:,1)./1000,res_list(:,2),10,'k','filled');
					xlabel('Distance (km)')
					ylabel('Residual (m)')
					title('Residual on k_{sn} fit')
					hold off

				elseif strcmp(pick_method,'slope_area')

					[bs,ba,bc,bd,bk]=sa_ksn(DEMc,Sn,A,C.chi,ak,smooth_distance);

					ax3=subplot(4,1,3);
					hold on
					plotdz(Sn,DEM,'dunit','km','Color',[0.5 0.5 0.5]);
					plotdz(Sn,DEMc,'dunit','km','Color','k');
					scatter((C.distance)./1000,C.elev,5,log10(C.area),'filled');
					xlabel('Distance from Mouth (km)')
					ylabel('Elevation (m)')
					legend('Unconditioned DEM','Conditioned DEM','Log Drainage Area','location','best');
					title('Long Profile')
					hold off

					ax2=subplot(4,1,2);
					hold on
					scatter(ba,bk,20,log10(ba),'filled','MarkerEdgeColor','k');
					xlabel('Log Area')
					ylabel('Auto k_{sn}');
					title('Log Area - Auto k_{sn}');
					set(ax2,'XScale','log','XDir','reverse');
					hold off

					ax1=subplot(4,1,1);
					hold on
					plot(C.chi,C.elev,'-k');
					scatter(C.chi,C.elev,10,log10(C.area),'filled');
					xlabel('Chi')
					ylabel('Elevation (m)')
					title('Chi - Z')
					hold off

					ax4=subplot(4,1,4);
					hold on
					scatter(ba,bs,20,log10(ba),'filled','MarkerEdgeColor','k');
					xlabel('Log Area');
					ylabel('Log Gradient');
					title(['Slope-Area: \theta = ' num2str(C.mn) ' : Pick Segments'],'Color','r');
					set(ax4,'YScale','log','XScale','log','XDir','reverse');
					ax4.XColor='Red';
					ax4.YColor='Red';
					hold off

					linkaxes([ax4,ax2],'x');
					colormap(ax1,'jet'); colormap(ax2,'jet'); colormap(ax3,'jet'); colormap(ax4,'jet');

					disp('    Select bounds for calculating channel steepnesses and press enter when completed')
					[av,~]=ginput;

					if isempty(av)
						if strcmp(theta_method,'ref')
							Cbf=ChiCalc(Sn,DEMc,A,1);
							ksn_list=[C.x C.y C.area ones(numel(C.x),1)*C.ks ones(numel(C.x),1)*C.ks_neg ones(numel(C.x),1)*C.ks_pos ...
								ones(numel(C.x),1)*C.mn ones(numel(C.x),1)*Cbf.mn];
						elseif strcmp(theta_method,'auto')
							ksn_list=[C.x C.y C.area ones(numel(C.x),1)*C.ks ones(numel(C.x),1)*C.ks_neg ones(numel(C.x),1)*C.ks_pos ...
								ones(numel(C.x),1)*C.mn ones(numel(C.x),1)*C.mn];
						end

						% Determine where ksn value fits into color scale and plot
						ksn_val=C.ks;

						if ksn_val > mksn;
							figure(f1)
							hold on
							plot(Sn,'Color',KSN_col(end,:),'LineWidth',2);
							hold off
						else
							edges=linspace(0,mksn,10);
							n=histc(ksn_val,edges);
							figure(f1)
							hold on
							plot(Sn,'Color',KSN_col(logical(n),:),'LineWidth',2);
							hold off	
						end

						[~,lbix]=min(C.chi);
						elbl=C.elev(lbix);

						figure(f2)
						subplot(4,1,1);
						hold on
						plot(C.chi,C.pred+elbl,'-k','LineWidth',2);
						hold off

						subplot(4,1,3);
						hold on
						plot((C.distance)/1000,C.pred+elbl,'-k','LineWidth',2);
						hold off

						subplot(4,1,4);
						hold on
						plot(C.area,ksn_val.*C.area.^(-C.mn),'-k','LineWidth',2);
						hold off

						res_list=[C.area C.res];
						bnd_ix=NaN;;

					else
						% Sort knickpoint list and construct bounds list
						avs=sortrows(av,'descend');
						bnds=vertcat(nanmax(C.area),avs,nanmin(C.area));

						num_bnds=numel(bnds);
						rc=C.chi;
						rx=C.x;
						ry=C.y;
						rd=C.distance;
						ra=C.area;
						for jj=1:num_bnds-1
							% Extract bounds
							lb=bnds(jj);
							rb=bnds(jj+1);

							% Clip out stream segment
							lb_dadist=sqrt(sum(bsxfun(@minus, ra, lb).^2,2));
							rb_dadist=sqrt(sum(bsxfun(@minus, ra, rb).^2,2));

							lbx=rx(lb_dadist==min(lb_dadist));
							lby=ry(lb_dadist==min(lb_dadist));

							rbx=rx(rb_dadist==min(rb_dadist));
							rby=ry(rb_dadist==min(rb_dadist));	

							lix=coord2ind(DEM,lbx,lby);
							LIX=GRIDobj(DEM,'logical');
							LIX.Z(lix)=true;	

							rix=coord2ind(DEM,rbx,rby);
							RIX=GRIDobj(DEM,'logical');
							RIX.Z(rix)=true;	

							Seg=modify(Sn,'downstreamto',RIX);
							Seg=modify(Seg,'upstreamto',LIX);

							% Construct bound list
							if jj<num_bnds-1
								bnd_ix(jj,1)=rix;
							end

							% Calculate chi to find ksn and bestfit concavity 
							if strcmp(theta_method,'ref')
								Cseg=ChiCalc(Seg,DEMc,A,1,ref_theta);
							elseif strcmp(theta_method,'auto')
								Cseg=ChiCalc(Seg,DEMc,A,1,C.mn);
							end
							Cbfseg=ChiCalc(Seg,DEMc,A,1);								

							% Determine where ksn value fits into color scale and plot
							ksn_val=Cseg.ks;

							if ksn_val > mksn;
								figure(f1)
								hold on
								plot(Seg,'Color',KSN_col(end,:),'LineWidth',2);
								hold off
							else
								edges=linspace(0,mksn,10);
								n=histc(ksn_val,edges);
								figure(f1)
								hold on
								plot(Seg,'Color',KSN_col(logical(n),:),'LineWidth',2);
								hold off	
							end

							ksn_nodes{jj,1}=[Cseg.x Cseg.y Cseg.area ones(numel(Cseg.x),1)*Cseg.ks ones(numel(Cseg.x),1)*Cseg.ks_neg ones(numel(Cseg.x),1)*Cseg.ks_pos ...
								ones(numel(Cseg.x),1)*Cseg.mn ones(numel(Cseg.x),1)*Cbfseg.mn];

							% Plot linear fits	
							rchi=rc(rb_dadist==min(rb_dadist));
							lchi=rc(lb_dadist==min(lb_dadist));
							segChi=linspace(lchi,rchi,numel(Cseg.chi));
							seg0Chi=linspace(0,max(Cseg.chi),numel(Cseg.chi));
							[~,lbix]=min(Cseg.chi);
							elbl=Cseg.elev(lbix);

							figure(f2)
							subplot(4,1,1);
							hold on
							plot(segChi,(seg0Chi.*ksn_val)+elbl,'-k','LineWidth',2);
							hold off

							seg_st=rd(lb_dadist==min(lb_dadist));
							subplot(4,1,3);
							hold on
							plot((Cseg.distance+seg_st)/1000,(Cseg.pred)+elbl,'-k','LineWidth',2);
							hold off

							subplot(4,1,4);
							hold on
							plot(Cseg.area,ksn_val.*Cseg.area.^(-1*Cseg.mn),'-k','LineWidth',2);
							hold off


							res_list{jj,1}=[Cseg.area Cseg.res];


						end

						ksn_list=vertcat(ksn_nodes{:});
						res_list=vertcat(res_list{:});
					end


					%% Plot result figure
					if display_slope_area
						figure(f2)
						subplot(4,1,2)
						hold on
						plot(res_list(:,1),ksn_list(:,4),'-k','LineWidth',2);
						hold off
					else
						figure(f2)
						subplot(3,1,2)
						hold on
						plot(res_list(:,1),ksn_list(:,4),'-k','LineWidth',2);
						hold off
					end

					f3=figure(3);
					set(f3,'Units','normalized','Position',[0.05 0.1 0.45 0.8],'renderer','painters');
					clf
					ax31=subplot(2,1,2);
					hold on
					s1=scatter(log10(ba),bk,20,'k','filled');
					p1=plot(log10(res_list(:,1)),ksn_list(:,4)-ksn_list(:,5),':k');
					plot(log10(res_list(:,1)),ksn_list(:,4)+ksn_list(:,6),':k');
					p2=plot(log10(res_list(:,1)),ksn_list(:,4),'-k','LineWidth',2);
					[ksn_vals,~,ksn_ix]=unique(ksn_list(:,4));
					a_means=accumarray(ksn_ix,res_list(:,1),[],@nanmean);
					for kk=1:numel(ksn_vals)
						text(log10(a_means(kk)),ksn_vals(kk),['k_{sn} = ' num2str(ksn_vals(kk))],...
							'VerticalAlignment','bottom','HorizontalAlignment','center');
					end
					xlabel('Log Area')
					ylabel('k_{sn}')
					title('k_{sn} - Log Area')
					legend([s1 p1 p2],{'Auto k_{sn}','k_{sn} uncertainty','k_{sn} of fit segments'},'location','best');
					set(ax31,'XScale','log','XDir','reverse');
					hold off

					ax32=subplot(2,1,1);
					hold on
					plot([log10(min(res_list(:,1))) log10(max(res_list(:,1)))],[0 0],'-k');
					scatter(log10(res_list(:,1)),res_list(:,2),10,'k','filled');
					xlabel('Log Area')
					ylabel('Residual (m)')
					title('Residual on k_{sn} fit')
					set(ax32,'XScale','log','XDir','Reverse');
					hold off

				end
			
				prompt='    Continue picking (Y), stop picking (N), or redo fit on this stream (R)? [Y]: ';
				str2=input(prompt,'s');
				if isempty(str2)
					str2 = 'Y';
					str1 = 'N';
					str3 = 'C';
					ksn_master{ii,1}=ksn_list;
					bnd_master{ii,1}=bnd_ix;
					if save_figures
						f2_name=['StreamFits_' num2str(ii) '.pdf'];
						f3_name=['StreamRsds_' num2str(ii) '.pdf'];
						print(f2,f2_name,'-dpdf','-fillpage');
						print(f3,f3_name,'-dpdf','-fillpage');
					end
					clear ksn_list ksn_nodes res_list bnd_ix;
					ii=ii+1;
				elseif strcmpi(str2,'Y');
					str1 = 'N';
					str3 = 'C';
					ksn_master{ii,1}=ksn_list;
					bnd_master{ii,1}=bnd_ix;
					if save_figures
						f2_name=['StreamFits_' num2str(ii) '.pdf'];
						f3_name=['StreamRsds_' num2str(ii) '.pdf'];
						print(f2,f2_name,'-dpdf','-fillpage');
						print(f3,f3_name,'-dpdf','-fillpage');
					end
					clear ksn_list ksn_nodes res_list bnd_ix;
					ii=ii+1;
				elseif strcmpi(str2,'N');
					str1 = 'N';
					str3 = 'C';
					ksn_master{ii,1}=ksn_list;
					bnd_master{ii,1}=bnd_ix;
					if save_figures
						f2_name=['StreamFits_' num2str(ii) '.pdf'];
						f3_name=['StreamRsds_' num2str(ii) '.pdf'];
						print(f2,f2_name,'-dpdf','-fillpage');
						print(f3,f3_name,'-dpdf','-fillpage');
					end
					clear ksn_list ksn_nodes res_list bnd_ix;
				elseif strcmpi(str2,'R');
					str3 = 'R';
					str2 = 'Y';
					clear ksn_list ksn_nodes res_list bnd_ix;
				end

				close figure 2
				close figure 3
			end
		end


	case 'preselected'
		% Initiate while loop value
		str1='R';

		if strcmp(theta_method,'ref')
			% Autocalculate ksn for comparison purposes
			[auto_ksn]=KSN_Quick(DEM,A,S,ref_theta);
		end

		for ii=1:num_ch

			while strcmpi(str1,'R');
	            
				chOI=s_ch(ii,:);

				% Build logical raster
				ix=coord2ind(DEM,chOI(:,1),chOI(:,2));
				IX=GRIDobj(DEM,'logical');
				IX.Z(ix)=true;

				% Extract stream of interest
				Sn=modify(S,'downstreamto',IX);

				% Build composite stream network of picked streams
				if strcmp(junction_method,'check')
					if ii>1
						[IIXX,~,~,Si]=intersectlocs(Sc,Sn);
						if isempty(IIXX)
							Sn=Sn;
							Sct=union(Sn,Sc,FD);
						else
							Sn=Si;

							if ~isempty(min_channel_length) & max(Sn.distance)<min_channel_length
								disp(['Skipping channel head ' num2str(ii) ', stream segment is too short']);
								break;
							end

							Sct=union(Sn,Sc,FD);
						end
					else
						Sct=Sn;
					end
				elseif strcmp(junction_method,'ignore')
					if ii>1
						Sct=union(Sn,Sc,FD);
					else
						Sct=Sn;
					end
				end

				%% Calculate chi and extract ksn data
				if strcmp(theta_method,'ref')
					C=ChiCalc(Sn,DEMc,A,1,ref_theta);
					ak=getnal(Sn,auto_ksn);
				elseif strcmp(theta_method,'auto')
					C=ChiCalc(Sn,DEMc,A,1);
					[auto_ksn]=KSN_Quick(DEM,A,S,C.mn);
					ak=getnal(Sn,auto_ksn);
				end

				%% Bin data
				[DAvg,KsnAvg]=BinAverage(Sn.distance,ak,smooth_distance);
				[~,CAvg]=BinAverage(C.distance,C.chi,smooth_distance);


				%% Initiate figure to pick bounds
				f2=figure(2);
				set(f2,'Units','normalized','Position',[0.5 0.1 0.45 0.8],'renderer','painters');
				clf	

				%% Main swith for different pick methods
				if strcmp(pick_method,'chi')

					if display_slope_area
						[bs,ba,bc,bd]=sa(DEMc,Sn,A,C.chi,smooth_distance);

						ax4=subplot(4,1,4);
						hold on
						scatter(ba,bs,20,bc,'filled','MarkerEdgeColor','k');
						xlabel('Log Area');
						ylabel('Log Gradient');
						title('Slope-Area');
						set(ax4,'YScale','log','XScale','log','XDir','reverse');
						hold off

						ax3=subplot(4,1,3);
						hold on
						plotdz(Sn,DEM,'dunit','km','Color',[0.5 0.5 0.5]);
						plotdz(Sn,DEMc,'dunit','km','Color','k');
						scatter((C.distance)./1000,C.elev,5,C.chi,'filled');
						xlabel('Distance from Mouth (km)')
						ylabel('Elevation (m)')
						legend('Unconditioned DEM','Conditioned DEM','Chi','location','best');
						title('Long Profile')
						hold off

						ax2=subplot(4,1,2);
						hold on
						scatter(CAvg,KsnAvg,20,CAvg,'filled','MarkerEdgeColor','k');
						xlabel('Chi')
						ylabel('Auto k_{sn}');
						title('Chi - Auto k_{sn}');
						hold off

						ax1=subplot(4,1,1);
						hold on
						plot(C.chi,C.elev,'-k');
						scatter(C.chi,C.elev,10,C.chi,'filled');
						xlabel('Chi')
						ylabel('Elevation (m)')
						title(['Chi - Z : \theta = ' num2str(C.mn) ' : Pick Segments'],'Color','r')
						ax1.XColor='Red';
						ax1.YColor='Red';
						hold off

						linkaxes([ax1,ax2],'x');
						colormap(ax1,'jet'); colormap(ax2,'jet'); colormap(ax3,'jet'); colormap(ax4,'jet');

					else
						ax3=subplot(3,1,3);
						hold on
						plotdz(Sn,DEM,'dunit','km','Color',[0.5 0.5 0.5]);
						plotdz(Sn,DEMc,'dunit','km','Color','k');
						scatter((C.distance)./1000,C.elev,5,C.chi,'filled')
						xlabel('Distance from Mouth (km)')
						ylabel('Elevation (m)')
						legend('Unconditioned DEM','Conditioned DEM','Chi','location','best');
						title('Long Profile')
						hold off

						ax2=subplot(3,1,2);
						hold on
						scatter(CAvg,KsnAvg,20,CAvg,'filled','MarkerEdgeColor','k');
						xlabel('Chi')
						ylabel('Auto k_{sn}');
						title('Chi - Auto k_{sn}');
						hold off

						ax1=subplot(3,1,1);
						hold on
						plot(C.chi,C.elev,'-k');
						scatter(C.chi,C.elev,10,C.chi,'filled');
						xlabel('Chi')
						ylabel('Elevation (m)')
						title(['Chi - Z : \theta = ' num2str(C.mn) ' : Pick Segments'],'Color','r')
						ax1.XColor='Red';
						ax1.YColor='Red';
						hold off

						linkaxes([ax1,ax2],'x');
						colormap(ax1,'jet'); colormap(ax2,'jet'); colormap(ax3,'jet');
					end	

					disp('    Select bounds for calculating channel steepnesses and press enter when completed')
					[cv,e]=ginput;

					if isempty(cv)
						if strcmp(theta_method,'ref')
							Cbf=ChiCalc(Sn,DEMc,A,1);
							ksn_list=[C.x C.y C.area ones(numel(C.x),1)*C.ks ones(numel(C.x),1)*C.ks_neg ones(numel(C.x),1)*C.ks_pos ...
								ones(numel(C.x),1)*C.mn ones(numel(C.x),1)*Cbf.mn];
						elseif strcmp(theta_method,'auto')
							ksn_list=[C.x C.y C.area ones(numel(C.x),1)*C.ks ones(numel(C.x),1)*C.ks_neg ones(numel(C.x),1)*C.ks_pos ...
								ones(numel(C.x),1)*C.mn ones(numel(C.x),1)*C.mn];
						end

						% Determine where ksn value fits into color scale and plot
						ksn_val=C.ks;

						[~,lbix]=min(C.chi);
						elbl=C.elev(lbix);
						if display_slope_area
							figure(f2)
							subplot(4,1,1);
							hold on
							plot(C.chi,C.pred+elbl,'-k','LineWidth',2);
							hold off

							subplot(4,1,3);
							hold on
							plot((C.distance)/1000,C.pred+elbl,'-k','LineWidth',2);
							hold off

							subplot(4,1,4);
							hold on
							plot(C.area,ksn_val.*C.area.^(-C.mn),'-k','LineWidth',2);
							hold off
						else
							figure(f2)
							subplot(3,1,1);
							hold on
							plot(C.chi,C.pred+elbl,'-k','LineWidth',2);
							hold off

							subplot(3,1,3);
							hold on
							plot((C.distance)/1000,C.pred+elbl,'-k','LineWidth',2);
							hold off
						end

						res_list=[C.chi C.res];
						bnd_ix=NaN;;

					else
						% Sort knickpoint list and construct bounds list
						cvs=sortrows(cv);
						bnds=vertcat(0,cvs,C.chi(1));

						num_bnds=numel(bnds);
						rc=C.chi;
						rx=C.x;
						ry=C.y;
						rd=C.distance;
						for jj=1:num_bnds-1
							% disp([' Calculating segment ' num2str(jj)])
							% Extract bounds
							lb=bnds(jj);
							rb=bnds(jj+1);

							% Clip out stream segment
							lb_chidist=sqrt(sum(bsxfun(@minus, rc, lb).^2,2));
							rb_chidist=sqrt(sum(bsxfun(@minus, rc, rb).^2,2));

							lbx=rx(lb_chidist==min(lb_chidist));
							lby=ry(lb_chidist==min(lb_chidist));

							rbx=rx(rb_chidist==min(rb_chidist));
							rby=ry(rb_chidist==min(rb_chidist));	

							lix=coord2ind(DEM,lbx,lby);
							LIX=GRIDobj(DEM,'logical');
							LIX.Z(lix)=true;	

							rix=coord2ind(DEM,rbx,rby);
							RIX=GRIDobj(DEM,'logical');
							RIX.Z(rix)=true;	

							Seg=modify(Sn,'downstreamto',RIX);
							Seg=modify(Seg,'upstreamto',LIX);

							% Construct bound list
							if jj<num_bnds-1
								bnd_ix(jj,1)=rix;
							end

							% Calculate chi to find ksn and bestfit concavity 
							if strcmp(theta_method,'ref')
								Cseg=ChiCalc(Seg,DEMc,A,1,ref_theta);
							elseif strcmp(theta_method,'auto')
								Cseg=ChiCalc(Seg,DEMc,A,1,C.mn);
							end
							Cbfseg=ChiCalc(Seg,DEMc,A,1);								

							% Determine where ksn value fits into color scale and plot
							ksn_val=Cseg.ks;

							ksn_nodes{jj,1}=[Cseg.x Cseg.y Cseg.area ones(numel(Cseg.x),1)*Cseg.ks ones(numel(Cseg.x),1)*Cseg.ks_neg ones(numel(Cseg.x),1)*Cseg.ks_pos ...
								ones(numel(Cseg.x),1)*Cseg.mn ones(numel(Cseg.x),1)*Cbfseg.mn];

							% Plot linear fits	
							rchi=rc(rb_chidist==min(rb_chidist));
							lchi=rc(lb_chidist==min(lb_chidist));
							segChi=linspace(lchi,rchi,numel(Cseg.chi));
							seg0Chi=linspace(0,max(Cseg.chi),numel(Cseg.chi));
							[~,lbix]=min(Cseg.chi);
							elbl=Cseg.elev(lbix);

							if display_slope_area
								figure(f2)
								subplot(4,1,1);
								hold on
								plot(segChi,(seg0Chi.*ksn_val)+elbl,'-k','LineWidth',2);
								hold off

								seg_st=rd(lb_chidist==min(lb_chidist));
								subplot(4,1,3);
								hold on
								plot((Cseg.distance+seg_st)/1000,(Cseg.pred)+elbl,'-k','LineWidth',2);
								hold off

								subplot(4,1,4);
								hold on
								plot(Cseg.area,ksn_val.*Cseg.area.^(-Cseg.mn),'-k','LineWidth',2);
								hold off
							else
								figure(f2)
								subplot(3,1,1);
								hold on
								plot(segChi,(seg0Chi.*ksn_val)+elbl,'-k','LineWidth',2);
								hold off

								seg_st=rd(lb_chidist==min(lb_chidist));
								subplot(3,1,3);
								hold on
								plot((Cseg.distance+seg_st)/1000,(Cseg.pred)+elbl,'-k','LineWidth',2);
								hold off
							end

							res_list{jj,1}=[Cseg.chi+lchi Cseg.res];	

						end

						ksn_list=vertcat(ksn_nodes{:});
						res_list=vertcat(res_list{:});
					end

					%% Plot result figure
					if display_slope_area
						figure(f2)
						subplot(4,1,2)
						hold on
						plot(res_list(:,1),ksn_list(:,4),'-k','LineWidth',2);
						hold off
					else
						figure(f2)
						subplot(3,1,2)
						hold on
						plot(res_list(:,1),ksn_list(:,4),'-k','LineWidth',2);
						hold off
					end

					f3=figure(3);
					set(f3,'Units','normalized','Position',[0.05 0.1 0.45 0.8],'renderer','painters');

					clf
					subplot(2,1,2)
					hold on
					s1=scatter(CAvg,KsnAvg,20,'k','filled');
					p1=plot(res_list(:,1),ksn_list(:,4)-ksn_list(:,5),':k');
					plot(res_list(:,1),ksn_list(:,4)+ksn_list(:,6),':k');
					p2=plot(res_list(:,1),ksn_list(:,4),'-k','LineWidth',2);
					[ksn_vals,~,ksn_ix]=unique(ksn_list(:,4));
					chi_means=accumarray(ksn_ix,res_list(:,1),[],@nanmean);
					for kk=1:numel(ksn_vals)
						text(chi_means(kk),ksn_vals(kk),['k_{sn} = ' num2str(ksn_vals(kk))],...
							'VerticalAlignment','bottom','HorizontalAlignment','center','Color','r');
					end
					xlabel('Chi')
					ylabel('k_{sn}')
					legend([s1 p1 p2],{'Auto k_{sn}','k_{sn} uncertainty','k_{sn} of fit segments'},'location','best');
					title('k_{sn} - Chi')
					hold off

					subplot(2,1,1)
					hold on
					plot([min(res_list(:,1)) max(res_list(:,1))],[0 0],'-k');
					scatter(res_list(:,1),res_list(:,2),10,'k','filled');
					xlabel('Chi')
					ylabel('Residual (m)')
					title('Residual on k_{sn} fit')
					hold off				

				elseif strcmp(pick_method,'stream')	

					if display_slope_area
						[bs,ba,bc,bd]=sa(DEMc,Sn,A,C.chi,smooth_distance);	

						ax4=subplot(4,1,4);
						hold on
						scatter(ba,bs,20,bd./1000,'filled','MarkerEdgeColor','k');
						xlabel('Log Area');
						ylabel('Log Gradient');
						title('Slope-Area');
						set(ax4,'XScale','log','YScale','log','XDir','reverse');
						hold off

						ax1=subplot(4,1,1);
						hold on
						plot(C.chi,C.elev,'Color',[0.5 0.5 0.5]);
						scatter(C.chi,C.elev,10,(C.distance)./1000,'filled');
						xlabel('Chi')
						ylabel('Elevation (m)')
						title(['Chi - Z : \theta = ' num2str(C.mn)])
						hold off

						ax2=subplot(4,1,2);
						hold on
						scatter(DAvg./1000,KsnAvg,20,DAvg./1000,'filled','MarkerEdgeColor','k');
						xlabel('Distance (km)')
						ylabel('Auto k_{sn}');
						title('Distance - Auto k_{sn}');
						hold off

						ax3=subplot(4,1,3);
						hold on
						plotdz(Sn,DEM,'dunit','km','Color',[0.5 0.5 0.5]);
						plotdz(Sn,DEMc,'dunit','km','Color','k');
						scatter((C.distance)./1000,C.elev,5,(C.distance)./1000,'filled');
						xlabel('Distance from Mouth (km)')
						ylabel('Elevation (m)')
						legend('Unconditioned DEM','Conditioned DEM','Stream Distance','location','best');
						title('Long Profile : Pick Segments','Color','r')
						ax3.XColor='Red';
						ax3.YColor='Red';
						hold off

						linkaxes([ax2,ax3],'x');
						colormap(ax1,'jet'); colormap(ax2,'jet'); colormap(ax3,'jet'); colormap(ax4,'jet')
					else
						ax1=subplot(3,1,1);
						hold on
						plot(C.chi,C.elev,'Color',[0.5 0.5 0.5]);
						scatter(C.chi,C.elev,10,(C.distance)./1000,'filled');
						xlabel('Chi')
						ylabel('Elevation (m)')
						title(['Chi - Z : \theta = ' num2str(C.mn)])
						hold off

						ax2=subplot(3,1,2);
						hold on
						scatter(DAvg./1000,KsnAvg,20,DAvg./1000,'filled','MarkerEdgeColor','k');
						xlabel('Distance (km)')
						ylabel('Auto k_{sn}');
						title('Distance - Auto k_{sn}');
						hold off

						ax3=subplot(3,1,3);
						hold on
						plotdz(Sn,DEM,'dunit','km','Color',[0.5 0.5 0.5]);
						plotdz(Sn,DEMc,'dunit','km','Color','k');
						scatter((C.distance)./1000,C.elev,5,(C.distance)./1000,'filled');
						xlabel('Distance from Mouth (km)')
						ylabel('Elevation (m)')
						legend('Unconditioned DEM','Conditioned DEM','Stream Distance','location','best');
						title('Long Profile : Pick Segments','Color','r')
						ax3.XColor='Red';
						ax3.YColor='Red';
						hold off

						linkaxes([ax2,ax3],'x');
						colormap(ax1,'jet'); colormap(ax2,'jet'); colormap(ax3,'jet');	
					end	

					linkaxes([ax2,ax3],'x');
					colormap(ax1,'jet'); colormap(ax2,'jet'); colormap(ax3,'jet');

					disp('    Select bounds for calculating channel steepnesses and press enter when completed')
					[d,e]=ginput;
					d=d*1000; % convert back to meters;

					if isempty(d)
						if strcmp(theta_method,'ref')
							Cbf=ChiCalc(Sn,DEMc,A,1);
							ksn_list=[C.x C.y C.area ones(numel(C.x),1)*C.ks ones(numel(C.x),1)*C.ks_neg ones(numel(C.x),1)*C.ks_pos ...
								ones(numel(C.x),1)*C.mn ones(numel(C.x),1)*Cbf.mn];
						elseif strcmp(theta_method,'auto')
							ksn_list=[C.x C.y C.area ones(numel(C.x),1)*C.ks ones(numel(C.x),1)*C.ks_neg ones(numel(C.x),1)*C.ks_pos ...
								ones(numel(C.x),1)*C.mn ones(numel(C.x),1)*C.mn];
						end

						% Determine where ksn value fits into color scale and plot
						ksn_val=C.ks;

						[~,lbix]=min(C.chi);
						elbl=C.elev(lbix);
						if display_slope_area
							figure(f2)
							subplot(4,1,1);
							hold on
							plot(C.chi,C.pred+elbl,'-k','LineWidth',2);
							hold off

							subplot(4,1,3);
							hold on
							plot((C.distance)./1000,C.pred+elbl,'-k','LineWidth',2);
							hold off

							subplot(4,1,4);
							hold on
							plot(C.area,ksn_val.*C.area.^(-C.mn),'-k','LineWidth',2);
							hold off							
						else
							figure(f2)
							subplot(3,1,1);
							hold on
							plot(C.chi,C.pred+elbl,'-k','LineWidth',2);
							hold off

							subplot(3,1,3);
							hold on
							plot((C.distance)./1000,C.pred+elbl,'-k','LineWidth',2);
							hold off
						end

						res_list=[C.chi C.res];
						bnd_ix=NaN;;

					else
						% Sort knickpoint list and construct bounds list
						ds=sortrows(d);
						bnds=vertcat(0,ds,max(Sn.distance));

						num_bnds=numel(bnds);
						rd=C.distance; 
						rx=C.x;
						ry=C.y; 
						rc=C.chi;
						for jj=1:num_bnds-1
							% disp([' Calculating segment ' num2str(jj)])
							% Extract bounds
							lb=bnds(jj);
							rb=bnds(jj+1);

							% Clip out stream segment
							lb_dist=sqrt(sum(bsxfun(@minus, rd, lb).^2,2));
							rb_dist=sqrt(sum(bsxfun(@minus, rd, rb).^2,2));

							lbx=rx(lb_dist==min(lb_dist));
							lby=ry(lb_dist==min(lb_dist));

							rbx=rx(rb_dist==min(rb_dist));
							rby=ry(rb_dist==min(rb_dist));	

							lix=coord2ind(DEM,lbx,lby);
							LIX=GRIDobj(DEM,'logical');
							LIX.Z(lix)=true;	

							rix=coord2ind(DEM,rbx,rby);
							RIX=GRIDobj(DEM,'logical');
							RIX.Z(rix)=true;

							% Construct bound list
							if jj<num_bnds-1
								bnd_ix(jj,1)=rix;
							end	

							Seg=modify(Sn,'downstreamto',RIX);
							Seg=modify(Seg,'upstreamto',LIX);

							% Calculate chi to find ksn and bestfit concavity 
							if strcmp(theta_method,'ref')
								Cseg=ChiCalc(Seg,DEMc,A,1,ref_theta);
							elseif strcmp(theta_method,'auto')
								Cseg=ChiCalc(Seg,DEMc,A,1,C.mn);
							end
							Cbfseg=ChiCalc(Seg,DEMc,A,1);

							% Determine where ksn value fits into color scale and plot
							ksn_val=Cseg.ks;

							ksn_nodes{jj,1}=[Cseg.x Cseg.y Cseg.area ones(numel(Cseg.x),1)*Cseg.ks ones(numel(Cseg.x),1)*Cseg.ks_neg ones(numel(Cseg.x),1)*Cseg.ks_pos ...
								ones(numel(Cseg.x),1)*Cseg.mn ones(numel(Cseg.x),1)*Cbfseg.mn];

							% Plot linear fits	
							rchi=rc(rb_dist==min(rb_dist));
							lchi=rc(lb_dist==min(lb_dist));
							ld=rd(lb_dist==min(lb_dist));
							segChi=linspace(lchi,rchi,numel(Cseg.chi));
							seg0Chi=linspace(0,max(Cseg.chi),numel(Cseg.chi));
							[~,lbix]=min(Cseg.chi);
							elbl=Cseg.elev(lbix);

							if display_slope_area
								figure(f2)
								subplot(4,1,1);
								hold on
								plot(segChi,(seg0Chi.*ksn_val)+elbl,'-k','LineWidth',2);
								hold off

								seg_st=rd(lb_dist==min(lb_dist));
								subplot(4,1,3);
								hold on
								plot((Cseg.distance+seg_st)/1000,(Cseg.pred)+elbl,'-k','LineWidth',2);
								hold off

								subplot(4,1,4);
								hold on
								plot(Cseg.area,ksn_val.*Cseg.area.^(-Cseg.mn),'-k','LineWidth',2);
								hold off
							else
								figure(f2)
								subplot(3,1,1);
								hold on
								plot(segChi,(seg0Chi.*ksn_val)+elbl,'-k','LineWidth',2);
								hold off

								seg_st=rd(lb_dist==min(lb_dist));
								subplot(3,1,3);
								hold on
								plot((Cseg.distance+seg_st)/1000,(Cseg.pred)+elbl,'-k','LineWidth',2);
								hold off
							end

							res_list{jj,1}=[Cseg.distance+ld Cseg.res];
						end

						ksn_list=vertcat(ksn_nodes{:});
						res_list=vertcat(res_list{:});
					end

					%% Plot fit result
					if display_slope_area
						figure(f2)
						subplot(4,1,2)
						hold on
						plot(res_list(:,1)./1000,ksn_list(:,4),'-k','LineWidth',2);
						hold off
					else
						figure(f2)
						subplot(3,1,2)
						hold on
						plot(res_list(:,1)./1000,ksn_list(:,4),'-k','LineWidth',2);
						hold off
					end

					f3=figure(3);
					set(f3,'Units','normalized','Position',[0.05 0.1 0.45 0.8],'renderer','painters');

					clf
					subplot(2,1,2)
					hold on
					s1=scatter(DAvg./1000,KsnAvg,20,'k','filled');
					p1=plot(res_list(:,1)./1000,ksn_list(:,4)-ksn_list(:,5),':k');
					plot(res_list(:,1)./1000,ksn_list(:,4)+ksn_list(:,6),':k');
					p2=plot(res_list(:,1)./1000,ksn_list(:,4),'-k','LineWidth',2);
					[ksn_vals,~,ksn_ix]=unique(ksn_list(:,4));
					d_means=accumarray(ksn_ix,res_list(:,1),[],@nanmean);
					for kk=1:numel(ksn_vals)
						text(d_means(kk)./1000,ksn_vals(kk),['k_{sn} = ' num2str(ksn_vals(kk))],...
							'VerticalAlignment','bottom','HorizontalAlignment','center');
					end
					xlabel('Distance (km)')
					ylabel('k_{sn}')
					title('k_{sn} - Distance')
					legend([s1 p1 p2],{'Auto k_{sn}','k_{sn} uncertainty','k_{sn} of fit segments'},'location','best');
					hold off

					subplot(2,1,1)
					hold on
					plot([min(res_list(:,1)./1000) max(res_list(:,1)./1000)],[0 0],'-k');
					scatter(res_list(:,1)./1000,res_list(:,2),10,'k','filled');
					xlabel('Distance (km)')
					ylabel('Residual (m)')
					title('Residual on k_{sn} fit')
					hold off

				elseif strcmp(pick_method,'slope_area')

					[bs,ba,bc,bd,bk]=sa_ksn(DEMc,Sn,A,C.chi,ak,smooth_distance);

					ax3=subplot(4,1,3);
					hold on
					plotdz(Sn,DEM,'dunit','km','Color',[0.5 0.5 0.5]);
					plotdz(Sn,DEMc,'dunit','km','Color','k');
					scatter((C.distance)./1000,C.elev,5,log10(C.area),'filled');
					xlabel('Distance from Mouth (km)')
					ylabel('Elevation (m)')
					legend('Unconditioned DEM','Conditioned DEM','Log Drainage Area','location','best');
					title('Long Profile')
					hold off

					ax2=subplot(4,1,2);
					hold on
					scatter(ba,bk,20,log10(ba),'filled','MarkerEdgeColor','k');
					xlabel('Log Area')
					ylabel('Auto k_{sn}');
					title('Log Area - Auto k_{sn}');
					set(ax2,'XScale','log','XDir','reverse');
					hold off

					ax1=subplot(4,1,1);
					hold on
					plot(C.chi,C.elev,'-k');
					scatter(C.chi,C.elev,10,log10(C.area),'filled');
					xlabel('Chi')
					ylabel('Elevation (m)')
					title('Chi - Z')
					hold off

					ax4=subplot(4,1,4);
					hold on
					scatter(ba,bs,20,log10(ba),'filled','MarkerEdgeColor','k');
					xlabel('Log Area');
					ylabel('Log Gradient');
					title(['Slope-Area: \theta = ' num2str(C.mn) ' : Pick Segments'],'Color','r');
					set(ax4,'YScale','log','XScale','log','XDir','reverse');
					ax4.XColor='Red';
					ax4.YColor='Red';
					hold off

					linkaxes([ax4,ax2],'x');
					colormap(ax1,'jet'); colormap(ax2,'jet'); colormap(ax3,'jet'); colormap(ax4,'jet');

					disp('    Select bounds for calculating channel steepnesses and press enter when completed')
					[av,~]=ginput;

					if isempty(av)
						if strcmp(theta_method,'ref')
							Cbf=ChiCalc(Sn,DEMc,A,1);
							ksn_list=[C.x C.y C.area ones(numel(C.x),1)*C.ks ones(numel(C.x),1)*C.ks_neg ones(numel(C.x),1)*C.ks_pos ...
								ones(numel(C.x),1)*C.mn ones(numel(C.x),1)*Cbf.mn];
						elseif strcmp(theta_method,'auto')
							ksn_list=[C.x C.y C.area ones(numel(C.x),1)*C.ks ones(numel(C.x),1)*C.ks_neg ones(numel(C.x),1)*C.ks_pos ...
								ones(numel(C.x),1)*C.mn ones(numel(C.x),1)*C.mn];
						end

						% Determine where ksn value fits into color scale and plot
						ksn_val=C.ks;

						[~,lbix]=min(C.chi);
						elbl=C.elev(lbix);

						figure(f2)
						subplot(4,1,1);
						hold on
						plot(C.chi,C.pred+elbl,'-k','LineWidth',2);
						hold off

						subplot(4,1,3);
						hold on
						plot((C.distance)/1000,C.pred+elbl,'-k','LineWidth',2);
						hold off

						subplot(4,1,4);
						hold on
						plot(C.area,ksn_val.*C.area.^(-C.mn),'-k','LineWidth',2);
						hold off

						res_list=[C.area C.res];
						bnd_ix=NaN;;

					else
						% Sort knickpoint list and construct bounds list
						avs=sortrows(av,'descend');
						bnds=vertcat(nanmax(C.area),avs,nanmin(C.area));

						num_bnds=numel(bnds);
						rc=C.chi;
						rx=C.x;
						ry=C.y;
						rd=C.distance;
						ra=C.area;
						for jj=1:num_bnds-1
							% Extract bounds
							lb=bnds(jj);
							rb=bnds(jj+1);

							% Clip out stream segment
							lb_dadist=sqrt(sum(bsxfun(@minus, ra, lb).^2,2));
							rb_dadist=sqrt(sum(bsxfun(@minus, ra, rb).^2,2));

							lbx=rx(lb_dadist==min(lb_dadist));
							lby=ry(lb_dadist==min(lb_dadist));

							rbx=rx(rb_dadist==min(rb_dadist));
							rby=ry(rb_dadist==min(rb_dadist));	

							lix=coord2ind(DEM,lbx,lby);
							LIX=GRIDobj(DEM,'logical');
							LIX.Z(lix)=true;	

							rix=coord2ind(DEM,rbx,rby);
							RIX=GRIDobj(DEM,'logical');
							RIX.Z(rix)=true;	

							Seg=modify(Sn,'downstreamto',RIX);
							Seg=modify(Seg,'upstreamto',LIX);

							% Construct bound list
							if jj<num_bnds-1
								bnd_ix(jj,1)=rix;
							end

							% Calculate chi to find ksn and bestfit concavity 
							if strcmp(theta_method,'ref')
								Cseg=ChiCalc(Seg,DEMc,A,1,ref_theta);
							elseif strcmp(theta_method,'auto')
								Cseg=ChiCalc(Seg,DEMc,A,1,C.mn);
							end
							Cbfseg=ChiCalc(Seg,DEMc,A,1);								

							% Determine where ksn value fits into color scale and plot
							ksn_val=Cseg.ks;

							ksn_nodes{jj,1}=[Cseg.x Cseg.y Cseg.area ones(numel(Cseg.x),1)*Cseg.ks ones(numel(Cseg.x),1)*Cseg.ks_neg ones(numel(Cseg.x),1)*Cseg.ks_pos ...
								ones(numel(Cseg.x),1)*Cseg.mn ones(numel(Cseg.x),1)*Cbfseg.mn];

							% Plot linear fits	
							rchi=rc(rb_dadist==min(rb_dadist));
							lchi=rc(lb_dadist==min(lb_dadist));
							segChi=linspace(lchi,rchi,numel(Cseg.chi));
							seg0Chi=linspace(0,max(Cseg.chi),numel(Cseg.chi));
							[~,lbix]=min(Cseg.chi);
							elbl=Cseg.elev(lbix);

							figure(f2)
							subplot(4,1,1);
							hold on
							plot(segChi,(seg0Chi.*ksn_val)+elbl,'-k','LineWidth',2);
							hold off

							seg_st=rd(lb_dadist==min(lb_dadist));
							subplot(4,1,3);
							hold on
							plot((Cseg.distance+seg_st)/1000,(Cseg.pred)+elbl,'-k','LineWidth',2);
							hold off

							subplot(4,1,4);
							hold on
							plot(Cseg.area,ksn_val.*Cseg.area.^(-1*Cseg.mn),'-k','LineWidth',2);
							hold off


							res_list{jj,1}=[Cseg.area Cseg.res];


						end

						ksn_list=vertcat(ksn_nodes{:});
						res_list=vertcat(res_list{:});
					end


					%% Plot result figure
					if display_slope_area
						figure(f2)
						subplot(4,1,2)
						hold on
						plot(res_list(:,1),ksn_list(:,4),'-k','LineWidth',2);
						hold off
					else
						figure(f2)
						subplot(3,1,2)
						hold on
						plot(res_list(:,1),ksn_list(:,4),'-k','LineWidth',2);
						hold off
					end

					f3=figure(3);
					set(f3,'Units','normalized','Position',[0.05 0.1 0.45 0.8],'renderer','painters');
					clf
					ax31=subplot(2,1,2);
					hold on
					s1=scatter(log10(ba),bk,20,'k','filled');
					p1=plot(log10(res_list(:,1)),ksn_list(:,4)-ksn_list(:,5),':k');
					plot(log10(res_list(:,1)),ksn_list(:,4)+ksn_list(:,6),':k');
					p2=plot(log10(res_list(:,1)),ksn_list(:,4),'-k','LineWidth',2);
					[ksn_vals,~,ksn_ix]=unique(ksn_list(:,4));
					a_means=accumarray(ksn_ix,res_list(:,1),[],@nanmean);
					for kk=1:numel(ksn_vals)
						text(log10(a_means(kk)),ksn_vals(kk),['k_{sn} = ' num2str(ksn_vals(kk))],...
							'VerticalAlignment','bottom','HorizontalAlignment','center');
					end
					xlabel('Log Area')
					ylabel('k_{sn}')
					title('k_{sn} - Log Area')
					legend([s1 p1 p2],{'Auto k_{sn}','k_{sn} uncertainty','k_{sn} of fit segments'},'location','best');
					set(ax31,'XScale','log','XDir','reverse');
					hold off

					ax32=subplot(2,1,1);
					hold on
					plot([log10(min(res_list(:,1))) log10(max(res_list(:,1)))],[0 0],'-k');
					scatter(log10(res_list(:,1)),res_list(:,2),10,'k','filled');
					xlabel('Log Area')
					ylabel('Residual (m)')
					title('Residual on k_{sn} fit')
					set(ax32,'XScale','log','XDir','Reverse');
					hold off
				% End pick method switch	
				end

				prompt='    Continue picking (Y) or redo fit on this stream (R)? [Y]: ';
				str2=input(prompt,'s');
				if isempty(str2)
					str1=[];
					ksn_master{ii,1}=ksn_list;
					bnd_master{ii,1}=bnd_ix;
					Sc=Sct;
					if save_figures
						f2_name=['StreamFits_' num2str(ii) '.pdf'];
						f3_name=['StreamRsds_' num2str(ii) '.pdf'];
						print(f2,f2_name,'-dpdf','-fillpage');
						print(f3,f3_name,'-dpdf','-fillpage');
					end
					clear ksn_list ksn_nodes res_list bnd_ix;
				elseif strcmpi(str2,'Y');
					str1=[];
					ksn_master{ii,1}=ksn_list;
					bnd_master{ii,1}=bnd_ix;
					if save_figures
						f2_name=['StreamFits_' num2str(ii) '.pdf'];
						f3_name=['StreamRsds_' num2str(ii) '.pdf'];
						print(f2,f2_name,'-dpdf','-fillpage');
						print(f3,f3_name,'-dpdf','-fillpage');
					end
					Sc=Sct;
					clear ksn_list ksn_nodes res_list bnd_ix;
				elseif strcmpi(str2,'R');
					str1 = 'R';
					clear ksn_list ksn_nodes res_list bnd_ix;
				end

				close figure 2
				close figure 3
			end
			% Reset for next loop
			str1='R';
		end

	% End switch between interactive vs provided
	end

	%%%%%%%%%%%%%%%%%%%%%%%%%%%%
	% Bundle, plot, and export %
	%%%%%%%%%%%%%%%%%%%%%%%%%%%%
	switch input_method
	case 'interactive'
		close figure 1
	end

	disp('Cleaning up and generating outputs...')
	% Add stream numbers to bound list and convert bound list
	bnd_list=cell(numel(bnd_master),1);
	for jj=1:numel(bnd_master);
		bnd=bnd_master{jj,1};
		if ~isnan(bnd)
			% Extract elevations
			bz=DEM.Z(bnd);
			% Find X Y
			[bx,by]=ind2coord(DEM,bnd);
			% Preserve linear index for later indexing
			bix=bnd;
			% Add River Number
			brm=ones(size(bnd)).*jj;
			% Compile and store
			bnd_list{jj,1}=[bx by bz brm bix];
		else
			bnd_list{jj,1}=[0 0 0 jj bnd];
		end
	end

	% Collapse bnd_list
	bnd_list=vertcat(bnd_list{:});

	% % % Convert bound list
	% if ~isempty(bnd_master{:,1})
	% 	bndl=[vertcat(bnd_master{:,1}) vertcat(bnd_master{:,2})];
	% 	bnd_z=DEM.Z(bndl(:,1));
	% 	[bnd_x,bnd_y]=ind2coord(DEM,bndl(:,1));
	% 	bnd_list=[bnd_x bnd_y bnd_z bndl(:,2)];
	% else
	% 	bndl=bnd_master{:,2};
	% 	bnd_list=[0 0 0 bndl];
	% end


	% Add Gradient to node list and clear NaNs
	for jj=1:numel(ksn_master)
		kmat=ksn_master{jj,1};
		kmat(isnan(kmat(:,1)),:)=[];
		gix=coord2ind(DEM,kmat(:,1),kmat(:,2));
		kmat=[kmat G.Z(gix) ones(size(kmat,1),1).*jj];
		ksn_master{jj,1}=kmat;
	end

	% Bundle all observations into single node list
	knl=vertcat(ksn_master{:});
	ix=coord2ind(DEM,knl(:,1),knl(:,2));

	% Build ksn and concavity raster
	ksnR=GRIDobj(DEM);
	ksnRn=GRIDobj(DEM);
	ksnRp=GRIDobj(DEM);
	thetaR=GRIDobj(DEM);
	segthetaR=GRIDobj(DEM);

	ksnR.Z(ix)=knl(:,4);
	ksnRn.Z(ix)=knl(:,5);
	ksnRp.Z(ix)=knl(:,6);
	thetaR.Z(ix)=knl(:,7);
	segthetaR.Z(ix)=knl(:,8);

	% Create KSN map structure and export shapefile
	KSN=STREAMobj2mapstruct(S,'seglength',smooth_distance,'attributes',...
		{'ksn' ksnR @mean 'ksn_neg' ksnRn @mean 'ksn_pos' ksnRp @mean 'uparea' (A.*(A.cellsize^2)) @mean 'gradient' G @mean 'theta' thetaR @mean 'seg_theta' segthetaR @mean});

	% Create knickpoint map structure and prepare bound output
	idx=~isnan(bnd_list(:,5));
	bnd_strc=bnd_list(idx,:);
	bnd_list(~idx,1)=NaN; bnd_list(~idx,2)=NaN; bnd_list(~idx,3)=NaN;
	bnd_list=bnd_list(:,[1:4]);

	if ~isempty(bnd_strc)
		KNK=struct;
		for jj=1:numel(bnd_strc(:,1));
			KNK(jj,1).Geometry='Point';
			KNK(jj,1).X=double(bnd_strc(jj,1));
			KNK(jj,1).Y=double(bnd_strc(jj,2));
			KNK(jj,1).Elev=double(bnd_strc(jj,3));
			KNK(jj,1).StrNum=double(bnd_strc(jj,4));
		end
		out_knick_name=[shape_name '_knicks.shp'];
		shapewrite(KNK,out_knick_name);
	end

	out_shape_name=[shape_name '.shp'];
	shapewrite(KSN,out_shape_name);


%FUNCTION END
end

function [OUT]=ChiCalc(S,DEM,A,a0,varargin)
	% Modified version of chiplot function by Wolfgang Schwanghart to remove unused options/outputs and 
	% to interpolate chi-z relationship so that chi values are equally spaced to avoid biasing of ksn fit
	% by clustering at high drainage areas 

	% nr of nodes in the entire stream network
	nrc = numel(S.x);
	M   = sparse(double(S.ix),double(S.ixc),true,nrc,nrc);
	% find outlet
	outlet = sum(M,2) == 0 & sum(M,1)'~=0;
	if nnz(outlet)>1
	    % there must not be more than one outlet (constraint could be removed
	    % in the future).
	    error('The stream network must not have more than one outlet');
	end


	% elevation values at nodes
	zx   = double(DEM.Z(S.IXgrid));
	% elevation at outlet
	zb   = double(DEM.Z(S.IXgrid(outlet)));
	% a is the term inside the brackets of equation 6b 
	a    = double(a0./(A.Z(S.IXgrid)*(A.cellsize.^2)));
	% x is the cumulative horizontal distance in upstream direction
	x    = S.distance;
	Lib = true(size(x));

	% Find bestfit concavity if no concavity provided or use provided concavity
	if isempty(varargin)
	    mn0  = 0.5; % initial value
	    mn   = fminsearch(@mnfit,mn0);
	else
		mn=varargin{1};
	end

	% calculate chi
	chi = netcumtrapz(x,a.^mn,S.ix,S.ixc);

	% Resample chi-elevation relationship using cubic spline interpolation
	chiF=chi(Lib);
	zabsF=zx(Lib)-zb;

	chiS=linspace(0,max(chiF),numel(chiF)).';
	try
		zS=spline(chiF,zabsF,chiS);
	catch
		% cubic spline will fail if segments is nearly straight, skip spline fit
		% in this case to avoid erroring out
		zS=zabsF;
		chiS=chiF;
	end

	OUT=struct;
	try
		ft=fittype('a*x');
		fobj=fit(chiS,zS,ft,'StartPoint',chiS\zS);
		BETA=coeffvalues(fobj);
		BETA_UNC=confint(fobj);
		OUT.ks   = BETA*a0^mn;
		OUT.ks_neg = (BETA*a0^mn)-(min(BETA_UNC)*a0^mn);
		OUT.ks_pos = (max(BETA_UNC)*a0^mn)-(BETA*a0^mn);
		OUT.mn   = mn;
	catch
		BETA = chiS\(zS);
		OUT.ks   = BETA*a0^mn;
		OUT.ks_neg = 0;
		OUT.ks_pos = 0;
		OUT.mn   = mn;
	end


	[OUT.x,...
	 OUT.y,...
	 OUT.chi,...
	 OUT.elev,...
	 OUT.elevbl,...
	 OUT.distance,...
	 OUT.pred,...
	 OUT.area] = STREAMobj2XY(S,chi,DEM,zx-zb,S.distance,BETA*chi,A.*(A.cellsize^2));
	 OUT.res = OUT.elevbl - OUT.pred;

	 	% Nested function for calculating mn ratio
	function sqres = mnfit(mn)
		% calculate chi with a given mn ratio
		% and integrate in upstream direction
		CHI = netcumtrapz(x(Lib),a(Lib).^mn,S.ix,S.ixc);%*ab.^mn
		% normalize both variables
		CHI = CHI ./ max(CHI);
		z   = zx(Lib)-zb;
		z   = z./max(z);
        sqres = sum((CHI - z).^2);
	end

end

function z = netcumtrapz(x,y,ix,ixc)
	% cumtrapz along upward direction in a directed tree network

	z = zeros(size(x));
	for lp = numel(ix):-1:1;
	    z(ix(lp)) = z(ixc(lp)) + (y(ixc(lp))+(y(ix(lp))-y(ixc(lp)))/2) *(abs(x(ixc(lp))-x(ix(lp))));
	end
end

function [Xavg,Yavg]=BinAverage(X,Y,bin_size);

	ix=~isnan(X);
	X=X(ix); Y=Y(ix);

	minX=min(X);
	maxX=max(X);

	b=[minX:bin_size:maxX+bin_size];

	try
		[idx]=discretize(X,b);
	catch
		[~,idx]=histc(X,b);
	end

	Xavg=accumarray(idx(:),X,[],@mean);
	Yavg=accumarray(idx(:),Y,[],@mean);
end

function [ksn]=KSN_Quick(DEM,A,S,theta_ref)

	zc=mincosthydrocon(S,DEM,'interp',0.1);
	DEMc=GRIDobj(DEM);
	DEMc.Z(DEMc.Z==0)=NaN;
	DEMc.Z(S.IXgrid)=zc;
	G=gradient8(DEMc);

	ksn=G./(A.*(A.cellsize^2)).^(-theta_ref);
	
end

function [bs,ba,bc,bd]=sa(DEM,S,A,C,bin_size)
	% Modified slope area function that uses the smooth length to
	%	to determine the number of bins and uses those same bins
	%	to find mean values of chi and distance for plotting
	%	purposes

	minX=min(S.distance);
	maxX=max(S.distance);
	b=[minX:bin_size:maxX+bin_size];

	numbins=round(max([numel(b) numel(S.IXgrid)/10]));

	an=getnal(S,A.*A.cellsize^2);
	z=getnal(S,DEM);
	gn=gradient(S,z,'unit','tangent'); % Already a conditioned DEM

	% Run through STREAMobj2XY so chi and everything else are same size
	[~,~,a,g,d]=STREAMobj2XY(S,an,gn,S.distance);
	% Remove NaNs
	a(isnan(a))=[];
	g(isnan(g))=[];
	d(isnan(d))=[];
	C(isnan(C))=[];

	mina=min(a);
	maxa=max(a);

    edges = logspace(log10(mina-0.1),log10(maxa+1),numbins+1);
    try
    	% histc is deprecated
    	[ix]=discretize(a,edges);
    catch
	    [~,ix] = histc(a,edges);
	end

	ba=accumarray(ix,a,[numbins 1],@median,nan);
	bs=accumarray(ix,g,[numbins 1],@(x) mean(x(~isnan(x))),nan);
	bd=accumarray(ix,d,[numbins 1],@mean,nan);
	bc=accumarray(ix,C,[numbins 1],@mean,nan);
end

function [bs,ba,bc,bd,bk]=sa_ksn(DEM,S,A,C,ak,bin_size);
	% Modified slope area function that uses the smooth length to
	%	to determine the number of bins and uses those same bins
	%	to find mean values of chi and distance for plotting
	%	purposes

	minX=min(S.distance);
	maxX=max(S.distance);
	b=[minX:bin_size:maxX+bin_size];

	numbins=round(max([numel(b) numel(S.IXgrid)/10]));

	an=getnal(S,A.*A.cellsize^2);
	z=getnal(S,DEM);
	gn=gradient(S,z,'unit','tangent'); % Already a conditioned DEM

	% Run through STREAMobj2XY so chi and everything else are same size
	[~,~,a,g,d,k]=STREAMobj2XY(S,an,gn,S.distance,ak);
	% Remove NaNs
	a(isnan(a))=[];
	g(isnan(g))=[];
	d(isnan(d))=[];
	C(isnan(C))=[];
	k(isnan(k))=[];

	mina=min(a);
	maxa=max(a);

    edges = logspace(log10(mina-0.1),log10(maxa+1),numbins+1);
    try
    	% histc is deprecated
    	[ix]=discretize(a,edges);
    catch
	    [~,ix] = histc(a,edges);
	end

	ba=accumarray(ix,a,[numbins 1],@median,nan);
	bs=accumarray(ix,g,[numbins 1],@(x) mean(x(~isnan(x))),nan);
	bd=accumarray(ix,d,[numbins 1],@mean,nan);
	bc=accumarray(ix,C,[numbins 1],@mean,nan);
	bk=accumarray(ix,k,[numbins 1],@mean,nan);
end
