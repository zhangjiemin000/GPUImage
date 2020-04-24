
#import "GPUImageVideoCamera.h"

void photoImageDataReleaseCallback(void *releaseRefCon, const void *baseAddress);
void GPUImagePhotoCreateResizedSampleBuffer(CVPixelBufferRef cameraFrame, CGSize finalSize, CMSampleBufferRef *sampleBuffer);


@interface GPUPhotoOutputCamera : GPUImageVideoCamera
// Only reliably set inside the context of the completion handler of one of the capture methods
@property (readonly) NSDictionary *currentCaptureMetadata;



- (void)capturePhotoProcessedUpToFilter:(GPUImageOutput <GPUImageInput> *)finalFilterInChain withImageOnGPUHandler:(void (^)(NSData *))block;
@end

