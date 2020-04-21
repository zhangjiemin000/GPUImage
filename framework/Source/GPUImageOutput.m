#import "GPUImageOutput.h"
#import "GPUImageMovieWriter.h"
#import "GPUImagePicture.h"
#import <mach/mach.h>

dispatch_queue_attr_t GPUImageDefaultQueueAttribute(void)
{
#if TARGET_OS_IPHONE
    if ([[[UIDevice currentDevice] systemVersion] compare:@"9.0" options:NSNumericSearch] != NSOrderedAscending)
    {
        return dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_DEFAULT, 0);
    }
#endif
    return nil;
}

void runOnMainQueueWithoutDeadlocking(void (^block)(void))
{
	if ([NSThread isMainThread])
	{
		block();
	}
	else
	{
		dispatch_sync(dispatch_get_main_queue(), block);
	}
}

/**
 * VideoProcssing Queue
 * 将block放置在串行队列当中
 * @param block
 */
void runSynchronouslyOnVideoProcessingQueue(void (^block)(void))
{
    //获取GPUImage Queue
    dispatch_queue_t videoProcessingQueue = [GPUImageContext sharedContextQueue];
#if !OS_OBJECT_USE_OBJC
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    if (dispatch_get_current_queue() == videoProcessingQueue)
#pragma clang diagnostic pop
#else
	if (dispatch_get_specific([GPUImageContext contextKey]))
#endif
    {
        block();
    } else {
        dispatch_sync(videoProcessingQueue, block);
    }
}

/**
 * 异步跑队列，对顺序不敏感的 block
 * @param block
 */
void runAsynchronouslyOnVideoProcessingQueue(void (^block)(void))
{
    dispatch_queue_t videoProcessingQueue = [GPUImageContext sharedContextQueue];
    
#if !OS_OBJECT_USE_OBJC
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    if (dispatch_get_current_queue() == videoProcessingQueue)
#pragma clang diagnostic pop
#else
    if (dispatch_get_specific([GPUImageContext contextKey]))
#endif
	{
		block();
	}else
	{
		dispatch_async(videoProcessingQueue, block);
	}
}

/**
 * 获取Context中定义的队列，同步执行 block
 * @param context
 * @param block
 */
void runSynchronouslyOnContextQueue(GPUImageContext *context, void (^block)(void))
{
    dispatch_queue_t videoProcessingQueue = [context contextQueue];
#if !OS_OBJECT_USE_OBJC
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    if (dispatch_get_current_queue() == videoProcessingQueue)
#pragma clang diagnostic pop
#else
        if (dispatch_get_specific([GPUImageContext contextKey]))
#endif
        {
            block();
        }else
        {
            dispatch_sync(videoProcessingQueue, block);
        }
}

/**
 * 获取Context中定义的队列，异步执行 block
 * @param context
 * @param block
 */
void runAsynchronouslyOnContextQueue(GPUImageContext *context, void (^block)(void))
{
    dispatch_queue_t videoProcessingQueue = [context contextQueue];
    
#if !OS_OBJECT_USE_OBJC
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    if (dispatch_get_current_queue() == videoProcessingQueue)
#pragma clang diagnostic pop
#else
        if (dispatch_get_specific([GPUImageContext contextKey]))
#endif
        {
            block();
        }else
        {
            dispatch_async(videoProcessingQueue, block);
        }
}

void reportAvailableMemoryForGPUImage(NSString *tag) 
{    
    if (!tag)
        tag = @"Default";
    
    struct task_basic_info info;
    
    mach_msg_type_number_t size = sizeof(info);
    
    kern_return_t kerr = task_info(mach_task_self(),
                                   
                                   TASK_BASIC_INFO,
                                   
                                   (task_info_t)&info,
                                   
                                   &size);    
    if( kerr == KERN_SUCCESS ) {        
        NSLog(@"%@ - Memory used: %u", tag, (unsigned int)info.resident_size); //in bytes
    } else {        
        NSLog(@"%@ - Error: %s", tag, mach_error_string(kerr));        
    }    
}

@implementation GPUImageOutput

@synthesize shouldSmoothlyScaleOutput = _shouldSmoothlyScaleOutput;
@synthesize shouldIgnoreUpdatesToThisTarget = _shouldIgnoreUpdatesToThisTarget;
@synthesize audioEncodingTarget = _audioEncodingTarget;
@synthesize targetToIgnoreForUpdates = _targetToIgnoreForUpdates;
@synthesize frameProcessingCompletionBlock = _frameProcessingCompletionBlock;
@synthesize enabled = _enabled;
@synthesize outputTextureOptions = _outputTextureOptions;

#pragma mark -
#pragma mark Initialization and teardown

- (id)init; 
{
	if (!(self = [super init]))
    {
		return nil;
    }

    targets = [[NSMutableArray alloc] init];
    targetTextureIndices = [[NSMutableArray alloc] init];
    _enabled = YES;
    allTargetsWantMonochromeData = YES;
    usingNextFrameForImageCapture = NO;
    
    // set default texture options
    //设置默认的GPU输出格式
    _outputTextureOptions.minFilter = GL_LINEAR;
    _outputTextureOptions.magFilter = GL_LINEAR;
    _outputTextureOptions.wrapS = GL_CLAMP_TO_EDGE;
    _outputTextureOptions.wrapT = GL_CLAMP_TO_EDGE;
    _outputTextureOptions.internalFormat = GL_RGBA;  //内部的颜色空间
    _outputTextureOptions.format = GL_BGRA;  //最终的格式
    _outputTextureOptions.type = GL_UNSIGNED_BYTE;

    return self;
}

- (void)dealloc 
{
    [self removeAllTargets];
}

#pragma mark -
#pragma mark Managing targets

- (void)setInputFramebufferForTarget:(id<GPUImageInput>)target atIndex:(NSInteger)inputTextureIndex;
{

    //满足GPUImageInput协议的所有实例
    [target setInputFramebuffer:[self framebufferForOutput] atIndex:inputTextureIndex];
}

/**
 * 返回对FrameBuffer的封装，封装了Framebuffer所有的操作
 * @return
 */
- (GPUImageFramebuffer *)framebufferForOutput;
{
    return outputFramebuffer;
}

- (void)removeOutputFramebuffer;
{
    outputFramebuffer = nil;
}

- (void)notifyTargetsAboutNewOutputTexture;
{
    for (id<GPUImageInput> currentTarget in targets)
    {
        NSInteger indexOfObject = [targets indexOfObject:currentTarget];
        NSInteger textureIndex = [[targetTextureIndices objectAtIndex:indexOfObject] integerValue];
        
        [self setInputFramebufferForTarget:currentTarget atIndex:textureIndex];
    }
}

- (NSArray*)targets;
{
	return [NSArray arrayWithArray:targets];
}

/**
 * addTarget，做的事情就是将本对象的输出纹理作为newTarget的输入纹理
 * @param newTarget
 */
- (void)addTarget:(id<GPUImageInput>)newTarget;
{
    //获取下一个可用的纹理Index，如果是TowInputTexture，则会判断是否已经使用过一个纹理了
    //获取Target下一个有效的纹理ID，纯色滤镜没有纹理ID
    NSInteger nextAvailableTextureIndex = [newTarget nextAvailableTextureIndex];
    //添加上去
    [self addTarget:newTarget atTextureLocation:nextAvailableTextureIndex];
    
    if ([newTarget shouldIgnoreUpdatesToThisTarget])
    {
        _targetToIgnoreForUpdates = newTarget;
    }
}

- (void)addTarget:(id<GPUImageInput>)newTarget atTextureLocation:(NSInteger)textureLocation;
{
    //如果已经有对应的target，则退出
    if([targets containsObject:newTarget])
    {
        return;
    }
    
    cachedMaximumOutputSize = CGSizeZero;
    runSynchronouslyOnVideoProcessingQueue(^{
        //设置FrameBuffer， 设置的输入buffer，为当前的输出buffer
        //将NewTarget的输入纹理设置为当前的输出纹理
        [self setInputFramebufferForTarget:newTarget atIndex:textureLocation];
        [targets addObject:newTarget];
        [targetTextureIndices addObject:[NSNumber numberWithInteger:textureLocation]];
        
        allTargetsWantMonochromeData = allTargetsWantMonochromeData && [newTarget wantsMonochromeInput];
    });
}

- (void)removeTarget:(id<GPUImageInput>)targetToRemove;
{
    if(![targets containsObject:targetToRemove])
    {
        return;
    }
    
    if (_targetToIgnoreForUpdates == targetToRemove)
    {
        _targetToIgnoreForUpdates = nil;
    }
    
    cachedMaximumOutputSize = CGSizeZero;
    
    NSInteger indexOfObject = [targets indexOfObject:targetToRemove];
    NSInteger textureIndexOfTarget = [[targetTextureIndices objectAtIndex:indexOfObject] integerValue];

    runSynchronouslyOnVideoProcessingQueue(^{
        [targetToRemove setInputSize:CGSizeZero atIndex:textureIndexOfTarget];
		[targetToRemove setInputRotation:kGPUImageNoRotation atIndex:textureIndexOfTarget];

        [targetTextureIndices removeObjectAtIndex:indexOfObject];
        [targets removeObject:targetToRemove];
        [targetToRemove endProcessing];
    });
}

- (void)removeAllTargets;
{
    cachedMaximumOutputSize = CGSizeZero;
    runSynchronouslyOnVideoProcessingQueue(^{
        for (id<GPUImageInput> targetToRemove in targets)
        {
            NSInteger indexOfObject = [targets indexOfObject:targetToRemove];
            NSInteger textureIndexOfTarget = [[targetTextureIndices objectAtIndex:indexOfObject] integerValue];
            
            [targetToRemove setInputSize:CGSizeZero atIndex:textureIndexOfTarget];
            [targetToRemove setInputRotation:kGPUImageNoRotation atIndex:textureIndexOfTarget];
        }
        [targets removeAllObjects];
        [targetTextureIndices removeAllObjects];
        
        allTargetsWantMonochromeData = YES;
    });
}

#pragma mark -
#pragma mark Manage the output texture

- (void)forceProcessingAtSize:(CGSize)frameSize;
{
    
}

- (void)forceProcessingAtSizeRespectingAspectRatio:(CGSize)frameSize;
{
}

#pragma mark -
#pragma mark Still image processing

- (void)useNextFrameForImageCapture;
{

}
/**
 * 这是一个抽象方法，看哪个实例继承了这个写法
 * @return
 */
- (CGImageRef)newCGImageFromCurrentlyProcessedOutput;
{
    return nil;
}

- (CGImageRef)newCGImageByFilteringCGImage:(CGImageRef)imageToFilter;
{
    GPUImagePicture *stillImageSource = [[GPUImagePicture alloc] initWithCGImage:imageToFilter];
    
    [self useNextFrameForImageCapture];
    [stillImageSource addTarget:(id<GPUImageInput>)self];
    [stillImageSource processImage];  //对新建的GPUImagePicture进行属性赋值
    
    CGImageRef processedImage = [self newCGImageFromCurrentlyProcessedOutput];
    
    [stillImageSource removeTarget:(id<GPUImageInput>)self];
    return processedImage;
}

- (BOOL)providesMonochromeOutput;
{
    return NO;
}

#pragma mark -
#pragma mark Platform-specific image output methods

#if TARGET_IPHONE_SIMULATOR || TARGET_OS_IPHONE

/**
 * 从Framebuffer中获取Image
 * @return
 */
- (UIImage *)imageFromCurrentFramebuffer;
{
    //获取当前设备的旋转方向
	UIDeviceOrientation deviceOrientation = [[UIDevice currentDevice] orientation];
    UIImageOrientation imageOrientation = UIImageOrientationLeft;
	switch (deviceOrientation)
    {
		case UIDeviceOrientationPortrait:
			imageOrientation = UIImageOrientationUp;
			break;
		case UIDeviceOrientationPortraitUpsideDown:
			imageOrientation = UIImageOrientationDown;
			break;
		case UIDeviceOrientationLandscapeLeft:
			imageOrientation = UIImageOrientationLeft;
			break;
		case UIDeviceOrientationLandscapeRight:
			imageOrientation = UIImageOrientationRight;
			break;
		default:
			imageOrientation = UIImageOrientationUp;
			break;
	}
    
    return [self imageFromCurrentFramebufferWithOrientation:imageOrientation];
}
/**
 * 真正的实现类，从当前FrameBuffer中获取图片
 * @param imageOrientation
 * @return
 */
- (UIImage *)imageFromCurrentFramebufferWithOrientation:(UIImageOrientation)imageOrientation;
{
    CGImageRef cgImageFromBytes = [self newCGImageFromCurrentlyProcessedOutput]; //这里是父类，所以没有实现这个方法，所以只能从子类的实现中，拿到CGImageRef的数据
    UIImage *finalImage = [UIImage imageWithCGImage:cgImageFromBytes scale:1.0 orientation:imageOrientation];
    CGImageRelease(cgImageFromBytes);
    
    return finalImage;
}

/**
 * 新建图片
 * @param imageToFilter
 * @return
 */
- (UIImage *)imageByFilteringImage:(UIImage *)imageToFilter;
{
    CGImageRef image = [self newCGImageByFilteringCGImage:[imageToFilter CGImage]];
    UIImage *processedImage = [UIImage imageWithCGImage:image scale:[imageToFilter scale] orientation:[imageToFilter imageOrientation]];
    CGImageRelease(image);
    return processedImage;
}

/**
 * UIImage -> CGImageRef
 * @param imageToFilter
 * @return
 */
- (CGImageRef)newCGImageByFilteringImage:(UIImage *)imageToFilter
{
    return [self newCGImageByFilteringCGImage:[imageToFilter CGImage]];
}

#else

- (NSImage *)imageFromCurrentFramebuffer;
{
    return [self imageFromCurrentFramebufferWithOrientation:UIImageOrientationLeft];
}

- (NSImage *)imageFromCurrentFramebufferWithOrientation:(UIImageOrientation)imageOrientation;
{
    CGImageRef cgImageFromBytes = [self newCGImageFromCurrentlyProcessedOutput];
    NSImage *finalImage = [[NSImage alloc] initWithCGImage:cgImageFromBytes size:NSZeroSize];
    CGImageRelease(cgImageFromBytes);
    
    return finalImage;
}

- (NSImage *)imageByFilteringImage:(NSImage *)imageToFilter;
{
    CGImageRef image = [self newCGImageByFilteringCGImage:[imageToFilter CGImageForProposedRect:NULL context:[NSGraphicsContext currentContext] hints:nil]];
    NSImage *processedImage = [[NSImage alloc] initWithCGImage:image size:NSZeroSize];
    CGImageRelease(image);
    return processedImage;
}

- (CGImageRef)newCGImageByFilteringImage:(NSImage *)imageToFilter
{
    return [self newCGImageByFilteringCGImage:[imageToFilter CGImageForProposedRect:NULL context:[NSGraphicsContext currentContext] hints:nil]];
}

#endif

#pragma mark -
#pragma mark Accessors

- (void)setAudioEncodingTarget:(GPUImageMovieWriter *)newValue;
{    
    _audioEncodingTarget = newValue;
    if( ! _audioEncodingTarget.hasAudioTrack )
    {
        _audioEncodingTarget.hasAudioTrack = YES;
    }
}

-(void)setOutputTextureOptions:(GPUTextureOptions)outputTextureOptions
{
    _outputTextureOptions = outputTextureOptions;
    //outputFramebuffer，是GPUFramebuffer的封装，对应Texture
    if( outputFramebuffer.texture )
    {
        //绑定纹理，将Framebuffer绑定到GL_TEXTURE_2D上
        glBindTexture(GL_TEXTURE_2D,  outputFramebuffer.texture);
        //_outputTextureOptions.format
        //_outputTextureOptions.internalFormat
        //_outputTextureOptions.magFilter
        //_outputTextureOptions.minFilter
        //_outputTextureOptions.type
        //设置属性
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, _outputTextureOptions.wrapS);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, _outputTextureOptions.wrapT);
        //
        glBindTexture(GL_TEXTURE_2D, 0);  //恢复到默认的状态，但是属性已经改变了，这个方法只做这个事情
    }
}

@end
