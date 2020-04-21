#import "GPUImageFilter.h"

extern NSString *const kGPUImageTwoInputTextureVertexShaderString;

/**
 * 两个InputFilter,两个input 的纹理，同一个GPU处理方法
 * 注意和其他的几种filter的区别
 */
@interface GPUImageTwoInputFilter : GPUImageFilter
{
    GPUImageFramebuffer *secondInputFramebuffer;

    GLint filterSecondTextureCoordinateAttribute;
    GLint filterInputTextureUniform2;
    GPUImageRotationMode inputRotation2;
    CMTime firstFrameTime, secondFrameTime;
    
    BOOL hasSetFirstTexture, hasReceivedFirstFrame, hasReceivedSecondFrame, firstFrameWasVideo, secondFrameWasVideo;
    BOOL firstFrameCheckDisabled, secondFrameCheckDisabled;
}

- (void)disableFirstFrameCheck;
- (void)disableSecondFrameCheck;

@end
