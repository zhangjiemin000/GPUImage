#import "GPUImageTwoPassFilter.h"

/**
 * 继承于GPUImageTwoPassFilter，
 */
@interface GPUImageTwoPassTextureSamplingFilter : GPUImageTwoPassFilter
{
    //定义了两套变量
    //就是定义了两套变量
    GLint verticalPassTexelWidthOffsetUniform, verticalPassTexelHeightOffsetUniform, horizontalPassTexelWidthOffsetUniform, horizontalPassTexelHeightOffsetUniform;
    GLfloat verticalPassTexelWidthOffset, verticalPassTexelHeightOffset, horizontalPassTexelWidthOffset, horizontalPassTexelHeightOffset;
    CGFloat _verticalTexelSpacing, _horizontalTexelSpacing;
}

// This sets the spacing between texels (in pixels) when sampling for the first. By default, this is 1.0
@property(readwrite, nonatomic) CGFloat verticalTexelSpacing, horizontalTexelSpacing;

@end
