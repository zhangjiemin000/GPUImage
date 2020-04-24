//
// Created by zhangjiemin on 2020/4/24.
// Copyright (c) 2020 Cell Phone. All rights reserved.
//

#import <GPUPhotoOutputCamera.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import <Photos/Photos.h>
#import "NewPhotoViewController.h"
#import "GPUImageView.h"
#import "GPUImageOutput.h"
#import "GPUImageSketchFilter.h"

#define mainScreenFrame [[UIScreen mainScreen] bounds]

@interface NewPhotoViewController()
@property (nonatomic, strong) UISlider *slider;
@property (nonatomic,strong) UIButton *takePhotoButton;
@property (nonatomic,strong) GPUImageView *gpuImageView;
@property (nonatomic,strong) GPUImageOutput<GPUImageInput> *filter, *secondFilter, *terminalFilter;
@property (nonatomic,strong) GPUPhotoOutputCamera *gpuPhotoOutputCamera;
@end


@implementation NewPhotoViewController {

}



-(void)viewDidLoad {
    [super viewDidLoad];
    [self setupView];
}


-(void)setupView{
    [self.view addSubview:self.gpuImageView];
    [self.view addSubview:self.takePhotoButton];
    [self.view addSubview:self.slider];

    [self setupCamera];
}

-(void)setupCamera {
    self.gpuPhotoOutputCamera = [[GPUPhotoOutputCamera alloc] initWithSessionPreset:AVCaptureSessionPresetPhoto cameraPosition:AVCaptureDevicePositionBack];
    self.gpuPhotoOutputCamera.outputImageOrientation = UIInterfaceOrientationPortrait;
    self.filter = [[GPUImageSketchFilter alloc] init];
    [self.gpuPhotoOutputCamera addTarget:self.filter];
    [self.filter addTarget:self.gpuImageView];
    [self.gpuPhotoOutputCamera startCameraCapture];
}


-(PHAssetCollectionChangeRequest *)getNextChangeRequest {

    PHFetchResult * result = [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeAlbum subtype:PHAssetCollectionSubtypeAlbumRegular options:nil];
    return [PHAssetCollectionChangeRequest changeRequestForAssetCollection:result[0]];
}




-(void)onHandlePic:(NSData*) processedJPEG {
    UIImage * image =  [UIImage imageWithData:processedJPEG];
    NSDictionary *propertise = self.gpuPhotoOutputCamera.currentCaptureMetadata;
    __weak typeof(self) weakself = self;
    [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
        UIImage *capturedImage = image;
//        NSMutableDictionary *removeOrientation = [propertise mutableCopy];
//        [removeOrientation removeObjectForKey:@"Orientation"];
        PHAssetCollectionChangeRequest * collectionChangeRequest = [self getNextChangeRequest];
        //获取Asset改变的Request
        PHAssetChangeRequest *request = [PHAssetChangeRequest creationRequestForAssetFromImage:capturedImage];
        //获取占位符
        PHObjectPlaceholder * placeholder = [request placeholderForCreatedAsset];

        [collectionChangeRequest addAssets:@[placeholder]];
    } completionHandler:^(BOOL success, NSError *error) {
        if(!success) {
            NSLog(error.description);
        }
//        [self.gpuPhotoOutputCamera startCameraCapture];
    }];
}

-(void)onTakePhoto {
    [self.takePhotoButton setEnabled:NO];
    [self.gpuPhotoOutputCamera capturePhotoProcessedUpToFilter:self.filter withImageOnGPUHandler:^(NSData *data) {

        if(data != NULL) {
            // Save to assets library
            if(PHPhotoLibrary.authorizationStatus == PHAuthorizationStatusNotDetermined) {
                [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
                    if(status==PHAuthorizationStatusAuthorized) {
                        dispatch_async(dispatch_get_global_queue(0, 0), ^{
                            [self onHandlePic:data];
                        });
                    }
                }];
                return;
            }else if(PHPhotoLibrary.authorizationStatus == PHAuthorizationStatusAuthorized) {
                dispatch_async(dispatch_get_global_queue(0,0), ^{
                    [self onHandlePic:data];
                });
            }else {
                [self.takePhotoButton setEnabled:YES];
                return;
            }
        }
    }];
}






#pragma mark - lazy loading
- (UISlider *)slider {
    if(_slider == nil) {
        _slider =[[UISlider alloc] initWithFrame:CGRectMake(25.0, mainScreenFrame.size.height - 50.0, mainScreenFrame.size.width - 50.0, 40.0)];
        _slider.maximumValue = 3;
        _slider.minimumValue = 0;
        _slider.value = 1;
    }
    return _slider;
}

- (UIButton *)takePhotoButton {
    if(_takePhotoButton == nil) {
        _takePhotoButton = [UIButton new];
        _takePhotoButton.frame = CGRectMake(round(mainScreenFrame.size.width / 2.0 - 150.0 / 2.0), mainScreenFrame.size.height - 80.0, 150.0, 40.0);
        [_takePhotoButton setTitle:@"take a photo" forState:UIControlStateNormal];
        _takePhotoButton.titleLabel.font = [UIFont systemFontOfSize:17];
        [_takePhotoButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        [_takePhotoButton setTitleColor:[UIColor greenColor] forState:UIControlStateHighlighted];

        [_takePhotoButton addTarget:self action:@selector(onTakePhoto) forControlEvents:UIControlEventTouchUpInside];


    }
    return _takePhotoButton;
}

- (GPUImageView *)gpuImageView {
    if(_gpuImageView == nil) {
        _gpuImageView = [[GPUImageView alloc] initWithFrame:mainScreenFrame];
        _gpuImageView.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    }
    return _gpuImageView;
}






@end