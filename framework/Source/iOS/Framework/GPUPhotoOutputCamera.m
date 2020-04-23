//
//  GPUPhotoOutputCamera.m
//  GPUImage
//
//  Created by zhangjiemin on 2020/4/23.
//  Copyright © 2020 Brad Larson. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GPUPhotoOutputCamera.h"

void stillImageDataReleaseCallback(const void *baseAddress) {
    free((void *) baseAddress);
}


void GPUImageCreateResizedSampleBuffer(CVPixelBufferRef cameraFrame, CGSize finalSize, CMSampleBufferRef *sampleBuffer) {
    // CVPixelBufferCreateWithPlanarBytes for YUV input
    CGSize originalSize = CGSizeMake(CVPixelBufferGetWidth(cameraFrame), CVPixelBufferGetHeight(cameraFrame));
    //准备锁住地址
    CVPixelBufferLockBaseAddress(cameraFrame, 0);
    //获取数据地址
    GLubyte *sourceImageBytes = CVPixelBufferGetBaseAddress(cameraFrame);
    //创建dataProvider
    CGDataProviderRef dataProvider = CGDataProviderCreateWithData(NULL, sourceImageBytes, CVPixelBufferGetBytesPerRow(cameraFrame) * originalSize.height, NULL);
    //获取颜色空间
    CGColorSpaceRef genericRGBColorspace = CGColorSpaceCreateDeviceRGB();
    //创建CGImage
    CGImageRef cgImageFromBytes = CGImageCreate((int) originalSize.width, (int) originalSize.height, 8, 32, CVPixelBufferGetBytesPerRow(cameraFrame), genericRGBColorspace, kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst, dataProvider, NULL, NO, kCGRenderingIntentDefault);
    //以上完成了CVpixelbuffer向CGImage的转换
    //创建新的图片
    GLubyte *imageData = (GLubyte *) calloc(1, (int) finalSize.width * (int) finalSize.height * 4);
    //创建CG下的Context
    CGContextRef imageContext = CGBitmapContextCreate(imageData, (int) finalSize.width, (int) finalSize.height, 8, (int) finalSize.width * 4, genericRGBColorspace, kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    //绘制Context,这里自动缩放了大小
    CGContextDrawImage(imageContext, CGRectMake(0.0, 0.0, finalSize.width, finalSize.height), cgImageFromBytes);
    //绘制图片到imageData，imageData竟然在Context中
    //释放CVPixelbuffer
    CGImageRelease(cgImageFromBytes);
    //释放imageContext
    CGContextRelease(imageContext);
    //释放颜色空间
    CGColorSpaceRelease(genericRGBColorspace);
    //释放dataProvider
    CGDataProviderRelease(dataProvider);

    //准备创建CMSampleBuffer
    CVPixelBufferRef pixel_buffer = NULL;
    //创建CVPixelBuffer
    CVPixelBufferCreateWithBytes(kCFAllocatorDefault, finalSize.width, finalSize.height, kCVPixelFormatType_32BGRA, imageData, finalSize.width * 4, stillImageDataReleaseCallback, NULL, NULL, &pixel_buffer);
    //创建CMdescription
    CMVideoFormatDescriptionRef videoInfo = NULL;
    //从pixelbuffer中获取videoInfo
    CMVideoFormatDescriptionCreateForImageBuffer(NULL, pixel_buffer, &videoInfo);
    //帧数,1表示第一帧，30表示1秒30帧
    CMTime frameTime = CMTimeMake(1, 30);
    CMSampleTimingInfo timing = {frameTime, frameTime, kCMTimeInvalid};
    //创建CMSampleBuffer
    CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault, pixel_buffer, YES, NULL, NULL, videoInfo, &timing, sampleBuffer);
    //取消锁住Frame
    CVPixelBufferUnlockBaseAddress(cameraFrame, 0);
    //释放对象
    CFRelease(videoInfo);
    CVPixelBufferRelease(pixel_buffer);
}


@interface GPUPhotoOutputCamera () <AVCapturePhotoCaptureDelegate>
@property(nonatomic, strong) AVCapturePhotoOutput *avCapturePhotoOutput;
@property(nonatomic, strong) AVCapturePhotoSettings *currentCaptureSettings;
@property(nonatomic, copy) void (^caputureResultBlock)(NSData * data);
@property(nonatomic, strong) GPUImageOutput <GPUImageInput> *finalFilterChain;
@end


@implementation GPUPhotoOutputCamera


- (id)initWithSessionPreset:(NSString *)sessionPreset cameraPosition:(AVCaptureDevicePosition)cameraPosition {

    if (!(self = [super initWithSessionPreset:sessionPreset cameraPosition:cameraPosition])) {
        return nil;
    }

    [self.captureSession beginConfiguration];
    self.currentCaptureSettings = [[AVCapturePhotoSettings alloc] init];
    self.currentCaptureSettings.flashMode = AVCaptureFlashModeOn;
    self.captureSessionPreset = sessionPreset;
    self.avCapturePhotoOutput = [[AVCapturePhotoOutput alloc] init];
    self.avCapturePhotoOutput.highResolutionCaptureEnabled = NO;
    self.avCapturePhotoOutput.livePhotoCaptureEnabled = NO;

    if (captureAsYUV && [GPUImageContext supportsFastTextureUpload]) {

//        BOOL supportsFullYUVRange = NO;
//        for (NSNumber * type in self.avCapturePhotoOutput.availablePhotoPixelFormatTypes) {
//            if([type intValue] == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) {
//                supportsFullYUVRange = YES;
//                break;
//            }
//        }


    } else {
        captureAsYUV = NO;


    }

    [self.captureSession addOutput:self.avCapturePhotoOutput];
    [self.captureSession commitConfiguration];
    return self;
}

- (instancetype)init {
    //预设分辨率
    if (!(self = [self initWithSessionPreset:AVCaptureSessionPresetPhoto cameraPosition:AVCaptureDevicePositionBack])) {
        return nil;
    }
    return self;
}


#pragma mark - AVCapturePhotoCaptureDelegate

- (void)captureOutput:(AVCapturePhotoOutput *)output didFinishProcessingPhotoSampleBuffer:(CMSampleBufferRef)photoSampleBuffer previewPhotoSampleBuffer:(CMSampleBufferRef)previewPhotoSampleBuffer resolvedSettings:(AVCaptureResolvedPhotoSettings *)resolvedSettings bracketSettings:(AVCaptureBracketedStillImageSettings *)bracketSettings error:(NSError *)error {

    if (previewPhotoSampleBuffer != NULL) {
        CVPixelBufferRef cameraFrame = CMSampleBufferGetImageBuffer(previewPhotoSampleBuffer);

        //获取CVPixelBuffer的Size
        CGSize sizeOfPhoto = CGSizeMake(CVPixelBufferGetWidth(cameraFrame), CVPixelBufferGetHeight(cameraFrame));
        CGSize scaleOnGPU = [GPUImageContext sizeThatFitsWithinATextureForSize:sizeOfPhoto];
        //需要转换
        if (!CGSizeEqualToSize(sizeOfPhoto, scaleOnGPU)) {
            CMSampleBufferRef cmSampleBuffer = NULL;
            if (CVPixelBufferGetPlaneCount(cameraFrame) == 0) {
                GPUImageCreateResizedSampleBuffer(cameraFrame, scaleOnGPU, &cmSampleBuffer);
            }
            dispatch_semaphore_signal(frameRenderingSemaphore);

            //为了导出图片
            [self.finalFilterChain useNextFrameForImageCapture];
            [self captureOutput:self.avCapturePhotoOutput didDropSampleBuffer:cmSampleBuffer fromConnection:self.avCapturePhotoOutput.connections.firstObject];

            dispatch_semaphore_wait(frameRenderingSemaphore, DISPATCH_TIME_FOREVER);
            [self processCMSampleBuffer:cmSampleBuffer];
        } else {
            dispatch_semaphore_signal(frameRenderingSemaphore);
            //为了导出图片
            [self.finalFilterChain useNextFrameForImageCapture];
            [self captureOutput:self.avCapturePhotoOutput didDropSampleBuffer:photoSampleBuffer fromConnection:self.avCapturePhotoOutput.connections.firstObject];

            dispatch_semaphore_wait(frameRenderingSemaphore, DISPATCH_TIME_FOREVER);
            [self processCMSampleBuffer:photoSampleBuffer];
        }
    }
}


#pragma  mark - private method

- (void)processCMSampleBuffer:(CMSampleBufferRef)capturedCMSampleBuffer {

    if (self.finalFilterChain != nil) {
        UIImage * image  = self.finalFilterChain.imageFromCurrentFramebuffer;
        NSData *data  =  UIImageJPEGRepresentation(image, 0.8);
        if(self.caputureResultBlock) {
            self.caputureResultBlock(data);
        }
    } else {
        self.caputureResultBlock(nil);
    }
}


- (void)capturePhotoProcessedUpToFilter:(GPUImageOutput <GPUImageInput> *)finalFilterInChain withImageOnGPUHandler:(void (^)(NSError *error))block {

    dispatch_semaphore_wait(frameRenderingSemaphore, DISPATCH_TIME_FOREVER);
    self.finalFilterChain = finalFilterInChain;
    [self.avCapturePhotoOutput capturePhotoWithSettings:self.currentCaptureSettings delegate:self];
    self.caputureResultBlock = block;
}


@end