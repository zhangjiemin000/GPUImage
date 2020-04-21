#import "GPUImageAdaptiveThresholdFilter.h"
#import "GPUImageFilter.h"
#import "GPUImageTwoInputFilter.h"
#import "GPUImageGrayscaleFilter.h"
#import "GPUImageBoxBlurFilter.h"

#if TARGET_IPHONE_SIMULATOR || TARGET_OS_IPHONE
NSString *const kGPUImageAdaptiveThresholdFragmentShaderString = SHADER_STRING
( 
 varying highp vec2 textureCoordinate;
 varying highp vec2 textureCoordinate2;
 
 uniform sampler2D inputImageTexture;
 uniform sampler2D inputImageTexture2; 
 
 void main()
 {
     highp float blurredInput = texture2D(inputImageTexture, textureCoordinate).r;
     highp float localLuminance = texture2D(inputImageTexture2, textureCoordinate2).r;
     //这里过滤了
     highp float thresholdResult = step(blurredInput - 0.05, localLuminance);  //如果localLuminance小于blurredInput则返回0.0，否则返回1.0
     
     gl_FragColor = vec4(vec3(thresholdResult), 1.0);
 }
);
#else
NSString *const kGPUImageAdaptiveThresholdFragmentShaderString = SHADER_STRING
(
 varying vec2 textureCoordinate;
 varying vec2 textureCoordinate2;
 
 uniform sampler2D inputImageTexture;
 uniform sampler2D inputImageTexture2;
 
 void main()
 {
     float blurredInput = texture2D(inputImageTexture, textureCoordinate).r;
     float localLuminance = texture2D(inputImageTexture2, textureCoordinate2).r;
     float thresholdResult = step(blurredInput - 0.05, localLuminance);
     
     gl_FragColor = vec4(vec3(thresholdResult), 1.0);
 }
);
#endif

@interface GPUImageAdaptiveThresholdFilter()
{
    GPUImageBoxBlurFilter *boxBlurFilter;
}
@end

@implementation GPUImageAdaptiveThresholdFilter

#pragma mark -
#pragma mark Initialization and teardown

- (id)init;
{
    if (!(self = [super init]))
    {
		return nil;
    }

    // First pass: reduce to luminance
    //luminance 统一都降低rgb的颜色
    GPUImageGrayscaleFilter *luminanceFilter = [[GPUImageGrayscaleFilter alloc] init];
    [self addFilter:luminanceFilter];
    
    // Second pass: perform a box blur
    boxBlurFilter = [[GPUImageBoxBlurFilter alloc] init];
    [self addFilter:boxBlurFilter];
    
    // Third pass: compare the blurred background luminance to the local value
    //结合两个输入，一个输出
    GPUImageFilter *adaptiveThresholdFilter = [[GPUImageTwoInputFilter alloc] initWithFragmentShaderFromString:kGPUImageAdaptiveThresholdFragmentShaderString];
    [self addFilter:adaptiveThresholdFilter];
    
    [luminanceFilter addTarget:boxBlurFilter];

    //两个输入。所以要被加两次
    [boxBlurFilter addTarget:adaptiveThresholdFilter];
    // To prevent double updating of this filter, disable updates from the sharp luminance image side
    [luminanceFilter addTarget:adaptiveThresholdFilter];

    //设置初始化Fitlers和终端Filters
    self.initialFilters = [NSArray arrayWithObject:luminanceFilter];
    self.terminalFilter = adaptiveThresholdFilter;
    
    return self;
}

#pragma mark -
#pragma mark Accessors

- (void)setBlurRadiusInPixels:(CGFloat)newValue;
{
    boxBlurFilter.blurRadiusInPixels = newValue;
}

- (CGFloat)blurRadiusInPixels;
{
    return boxBlurFilter.blurRadiusInPixels;
}

@end
