function VO = resize_img_rotate(imnames, Voxdim, BB, ismask, interp)
%  resize_img -- resample images to have specified voxel dims and BBox
% resize_img(imnames, voxdim, bb, ismask)
%
% Output images will be prefixed with 'r', and will have voxel dimensions
% equal to voxdim. Use NaNs to determine voxdims from transformation matrix
% of input image(s).
% If bb == nan(2,3), bounding box will include entire original image
% Origin will move appropriately. Use world_bb to compute bounding box from
% a different image.
%
% Pass ismask=true to re-round binary mask values (avoid
% growing/shrinking masks due to linear interp)
%
% See also voxdim, world_bb

% Based on John Ashburner's reorient.m
% http://www.sph.umich.edu/~nichols/JohnsGems.html#Gem7
% http://www.sph.umich.edu/~nichols/JohnsGems5.html#Gem2
% Adapted by Ged Ridgway -- email bugs to drc.spm@gmail.com

% This version doesn't check spm_flip_analyze_images -- the handedness of
% the output image and matrix should match those of the input.
%

% modified by Siawoosh Mohammadi 06/05/2014
% To ensure that the same voxel-sign is used after interpolation
% To distinguish this step from coreg, if is written out with an "i"

% Check spm version:
if exist('spm_select','file') % should be true for spm5
    spm5 = 1;
elseif exist('spm_get','file') % should be true for spm2
    spm5 = 0;
else
    error('Can''t find spm_get or spm_select; please add SPM to path')
end

 spm_get_defaults;

% prompt for missing arguments
if(~exist('imnames','var'))
    if ( isempty(char(imnames)) )
        if spm5
            imnames = spm_select(inf, 'image', 'Choose images to resize');
        else
            imnames = spm_get(inf, 'img', 'Choose images to resize');
        end
    end
end
% check if inter fig already open, don't close later if so...
Fint = spm_figure('FindWin', 'Interactive'); Fnew = [];
if ( ~exist('Voxdim', 'var') || isempty(Voxdim) )
    Fnew = spm_figure('GetWin', 'Interactive');
    Voxdim = spm_input('Vox Dims (NaN for "as input")? ',...
        '+1', 'e', '[nan nan nan]', 3);
end
if ( ~exist('BB', 'var') || isempty(BB) )
    Fnew = spm_figure('GetWin', 'Interactive');
    BB = spm_input('Bound Box (NaN => original)? ',...
        '+1', 'e', '[nan nan nan; nan nan nan]', [2 3]);
end
if ~exist('ismask', 'var')
    ismask = false;
end
if isempty(ismask)
    ismask = false;
end
if ~exist('interp', 'var')
    % Default to 7th order sinc interpolation:
    interp = -7;
end
if isempty(interp)
    interp = -7;
end

% reslice images one-by-one
vols = spm_vol(imnames);
for V=vols'
    % (copy to allow defaulting of NaNs differently for each volume)
    % voxdim = sign(ones(1,3)*V.mat(1:3,1:3)).*abs(Voxdim); % SM
    voxdim = Voxdim; % SM
    bb = BB;
    % default voxdim to current volume's voxdim, (from mat parameters)
    if any(isnan(voxdim))
        vprm = spm_imatrix(V.mat);
        vvoxdim = vprm(7:9);
        voxdim(isnan(voxdim)) = vvoxdim(isnan(voxdim));
    end
    voxdim = voxdim(:)';

    mn = bb(1,:);
    mx = bb(2,:);
    
    % default BB to current volume's
    if any(isnan(bb(:)))
        vbb = world_bb(V);
        vmn = vbb(1,:);
        vmx = vbb(2,:);
        % SM 
        sgn = sign(voxdim);
        vpos = find(sgn == -1);
        for inx = vpos
            vmn(inx) = vbb(2,inx);
            vmx(inx) = vbb(1,inx);
        end
         % SM
        mn(isnan(mn)) = vmn(isnan(mn));
        mx(isnan(mx)) = vmx(isnan(mx));
    end

    % voxel [1 1 1] of output should map to BB mn
    % (the combination of matrices below first maps [1 1 1] to [0 0 0])
    tt      = sqrt(sum(V.mat(1:3,1:3).^2));
    para    = spm_imatrix(V.mat);
%    mat     = spm_matrix([mn -para(4:6) voxdim])*spm_matrix([-1 -1 -1]);
    mat     = spm_matrix([para(1:6) sign(para(7:9)).*voxdim]);

%     matid   = spm_matrix([mn 0 0 0 tt])*spm_matrix([-1 -1 -1]);
%     Mid = inv(inv(matid)*V.mat);
%     Mid = inv(inv(matid)*V.mat);

    

    
    % voxel-coords of BB mx gives number of voxels required
    % (round up if more than a tenth of a voxel over)
    
    % SM
%     % imgdim = ceil(mat \ [mx 1]' - 0.1)';
%     imgdim = abs(ceil(mat \ [mx 1]' - 0.1)'); % SM
%     imgdim = imgdim - 1;
    imgdim =  abs(ceil((tt./voxdim).*V.dim)); % SM
    % SM
    
    % output image
    VO            = V;
    [pth,nam,ext] = fileparts(V.fname);
    VO.fname      = fullfile(pth,['i' nam ext]);
    VO.dim(1:3)   = imgdim(1:3);
    VO.mat        = mat;    
    VO = spm_create_vol(VO);
    spm_progress_bar('Init',imgdim(3),'reslicing...','planes completed');
    % f1 = figure;
    for i = 1:imgdim(3)
        M = inv(spm_matrix([0 0 -i 0 0 0 1 1 1])*inv(VO.mat)*V.mat);
        img = spm_slice_vol(V, M, imgdim(1:2), interp);
      %   imagesc(rot90(img),[0 1000]);
      %   pause(0.2)
        if ismask
            img = round(img);
        end
        spm_write_plane(VO, img, i);
        spm_progress_bar('Set', i)
    end
    % close(f1);
    spm_progress_bar('Clear');
end
% call spm_close_vol if spm2
if ~spm5
    spm_close_vol(VO);
end
if (isempty(Fint) && ~isempty(Fnew))
    % interactive figure was opened by this script, so close it again.
    close(Fnew);
end
disp('Done.')


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function bb = world_bb(V)
%  world-bb -- get bounding box in world (mm) coordinates

d = V.dim(1:3);
% corners in voxel-space
c = [ 1    1    1    1
    1    1    d(3) 1
    1    d(2) 1    1
    1    d(2) d(3) 1
    d(1) 1    1    1
    d(1) 1    d(3) 1
    d(1) d(2) 1    1
    d(1) d(2) d(3) 1 ]';
% corners in world-space
tc = V.mat(1:3,1:4)*c;

% bounding box (world) min and max
mn = min(tc,[],2)';
mx = max(tc,[],2)';
bb = [mn; mx];
