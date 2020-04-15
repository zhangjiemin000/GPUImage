#import "GPUImagePicture.h"

@implementation GPUImagePicture

#pragma mark -
#pragma mark Initialization and teardown

/**
 * 从URL中获取Image
 * @param url
 * @return
 */
- (id)initWithURL:(NSURL *)url;
{
    NSData *imageData = [[NSData alloc] initWithContentsOfURL:url];
    
    if (!(self = [self initWithData:imageData]))
    {
        return nil;
    }
    
    return self;
}

/**
 * 从2进制中获取UIImage，并赋值
 * @param imageData
 * @return
 */
- (id)initWithData:(NSData *)imageData;
{
    UIImage *inputImage = [[UIImage alloc] initWithData:imageData];
    
    if (!(self = [self initWithImage:inputImage]))
    {
		return nil;
    }
    
    return self;
}

- (id)initWithImage:(UIImage *)newImageSource;
{
    //init Image ，将UIImage绘制到texture上
    if (!(self = [self initWithImage:newImageSource smoothlyScaleOutput:NO]))
    {
		return nil;
    }
    
    return self;
}

- (id)initWithCGImage:(CGImageRef)newImageSource;
{
    //init Image ，将UIImage绘制到texture上
    if (!(self = [self initWithCGImage:newImageSource smoothlyScaleOutput:NO]))
    {
		return nil;
    }
    return self;
}

- (id)initWithImage:(UIImage *)newImageSource smoothlyScaleOutput:(BOOL)smoothlyScaleOutput;
{
    //init Image ，将UIImage绘制到texture上
    return [self initWithCGImage:[newImageSource CGImage] smoothlyScaleOutput:smoothlyScaleOutput];
}

- (id)initWithCGImage:(CGImageRef)newImageSource smoothlyScaleOutput:(BOOL)smoothlyScaleOutput;
{
    //init Image ，将UIImage绘制到texture上
    return [self initWithCGImage:newImageSource smoothlyScaleOutput:smoothlyScaleOutput removePremultiplication:NO];
}

- (id)initWithImage:(UIImage *)newImageSource removePremultiplication:(BOOL)removePremultiplication;
{
    return [self initWithCGImage:[newImageSource CGImage] smoothlyScaleOutput:NO removePremultiplication:removePremultiplication];
}

- (id)initWithCGImage:(CGImageRef)newImageSource removePremultiplication:(BOOL)removePremultiplication;
{
    return [self initWithCGImage:newImageSource smoothlyScaleOutput:NO removePremultiplication:removePremultiplication];
}

- (id)initWithImage:(UIImage *)newImageSource smoothlyScaleOutput:(BOOL)smoothlyScaleOutput removePremultiplication:(BOOL)removePremultiplication;
{
    return [self initWithCGImage:[newImageSource CGImage] smoothlyScaleOutput:smoothlyScaleOutput removePremultiplication:removePremultiplication];
}

/**
 * 从CGIamge中创建自身，有smoothlyScaleOutput和removePremultipication的配置
 * @param newImageSource
 * @param smoothlyScaleOutput
 * @param removePremultiplication
 * @return
 */
- (id)initWithCGImage:(CGImageRef)newImageSource smoothlyScaleOutput:(BOOL)smoothlyScaleOutput removePremultiplication:(BOOL)removePremultiplication;
{
    if (!(self = [super init]))
    {
		return nil;
    }
    
    hasProcessedImage = NO;
    self.shouldSmoothlyScaleOutput = smoothlyScaleOutput;
    //创建信号量0
    imageUpdateSemaphore = dispatch_semaphore_create(0);
    //这个是为了从异步到同步
    dispatch_semaphore_signal(imageUpdateSemaphore);


    // TODO: Dispatch this whole thing asynchronously to move image loading off main thread
    CGFloat widthOfImage = CGImageGetWidth(newImageSource);
    CGFloat heightOfImage = CGImageGetHeight(newImageSource);

    // If passed an empty image reference, CGContextDrawImage will fail in future versions of the SDK.
    NSAssert( widthOfImage > 0 && heightOfImage > 0, @"Passed image must not be empty - it should be at least 1px tall and wide");
    
    pixelSizeOfImage = CGSizeMake(widthOfImage, heightOfImage);
    CGSize pixelSizeToUseForTexture = pixelSizeOfImage;
    
    BOOL shouldRedrawUsingCoreGraphics = NO;
    
    // For now, deal with images larger than the maximum texture size by resizing to be within that limit
    CGSize scaledImageSizeToFitOnGPU = [GPUImageContext sizeThatFitsWithinATextureForSize:pixelSizeOfImage];
    if (!CGSizeEqualToSize(scaledImageSizeToFitOnGPU, pixelSizeOfImage))
    {
        pixelSizeOfImage = scaledImageSizeToFitOnGPU;
        pixelSizeToUseForTexture = pixelSizeOfImage;
        shouldRedrawUsingCoreGraphics = YES;
    }
    
    if (self.shouldSmoothlyScaleOutput)
    {
        //如果需要平滑缩放，则会放大到2的倍数的大小
        // In order to use mipmaps, you need to provide power-of-two textures, so convert to the next largest power of two and stretch to fill
        CGFloat powerClosestToWidth = ceil(log2(pixelSizeOfImage.width));
        CGFloat powerClosestToHeight = ceil(log2(pixelSizeOfImage.height));
        //powerClosetToWidth代表是2的指数值
        pixelSizeToUseForTexture = CGSizeMake(pow(2.0, powerClosestToWidth), pow(2.0, powerClosestToHeight));
        
        shouldRedrawUsingCoreGraphics = YES;
    }
    
    GLubyte *imageData = NULL;
    CFDataRef dataFromImageDataProvider = NULL;
    GLenum format = GL_BGRA;
    BOOL isLitteEndian = YES;
    BOOL alphaFirst = NO;
    BOOL premultiplied = NO;

    if (!shouldRedrawUsingCoreGraphics) {
        //如果不需要使用CG来重新绘制，则会这样
        /* Check that the memory layout is compatible with GL, as we cannot use glPixelStore to
         * tell GL about the memory layout with GLES.
         */
        if (CGImageGetBytesPerRow(newImageSource) != CGImageGetWidth(newImageSource) * 4 ||
            CGImageGetBitsPerPixel(newImageSource) != 32 ||
            CGImageGetBitsPerComponent(newImageSource) != 8)
        {
            //如果格式不正确
            shouldRedrawUsingCoreGraphics = YES;
        } else {
            /* Check that the bitmap pixel format is compatible with GL */
            CGBitmapInfo bitmapInfo = CGImageGetBitmapInfo(newImageSource);
            if ((bitmapInfo & kCGBitmapFloatComponents) != 0) {
                /* We don't support float components for use directly in GL */
                //对于不支持的，只能进行重新绘制
                shouldRedrawUsingCoreGraphics = YES;
            } else {
                CGBitmapInfo byteOrderInfo = bitmapInfo & kCGBitmapByteOrderMask;
                if (byteOrderInfo == kCGBitmapByteOrder32Little) {
                    //判断是否是小格式
                    /* Little endian, for alpha-first we can use this bitmap directly in GL */
                    CGImageAlphaInfo alphaInfo = bitmapInfo & kCGBitmapAlphaInfoMask;
                    if (alphaInfo != kCGImageAlphaPremultipliedFirst && alphaInfo != kCGImageAlphaFirst &&
                        alphaInfo != kCGImageAlphaNoneSkipFirst) {
                        //需要保证A在前
                        shouldRedrawUsingCoreGraphics = YES;
                    }
                } else if (byteOrderInfo == kCGBitmapByteOrderDefault || byteOrderInfo == kCGBitmapByteOrder32Big) {
					isLitteEndian = NO;
                    /* Big endian, for alpha-last we can use this bitmap directly in GL */
                    CGImageAlphaInfo alphaInfo = bitmapInfo & kCGBitmapAlphaInfoMask;
                    if (alphaInfo != kCGImageAlphaPremultipliedLast && alphaInfo != kCGImageAlphaLast &&
                        alphaInfo != kCGImageAlphaNoneSkipLast) {
                        shouldRedrawUsingCoreGraphics = YES;
                    } else {
                        /* Can access directly using GL_RGBA pixel format */
						premultiplied = alphaInfo == kCGImageAlphaPremultipliedLast || alphaInfo == kCGImageAlphaPremultipliedLast;
						alphaFirst = alphaInfo == kCGImageAlphaFirst || alphaInfo == kCGImageAlphaPremultipliedFirst;
						format = GL_RGBA;
                    }
                }
            }
        }
    }
    
    //    CFAbsoluteTime elapsedTime, startTime = CFAbsoluteTimeGetCurrent();
    
    if (shouldRedrawUsingCoreGraphics)    //如果需要重新绘制
    {
        // For resized or incompatible image: redraw
        //申请字符容量
        imageData = (GLubyte *) calloc(1, (int)pixelSizeToUseForTexture.width * (int)pixelSizeToUseForTexture.height * 4);
        //获取设备的RGB颜色空间
        CGColorSpaceRef genericRGBColorspace = CGColorSpaceCreateDeviceRGB();
        //新建上下文
        CGContextRef imageContext = CGBitmapContextCreate(imageData,
                (size_t)pixelSizeToUseForTexture.width,
                (size_t)pixelSizeToUseForTexture.height, 8,
                (size_t)pixelSizeToUseForTexture.width * 4,
                genericRGBColorspace,
                kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
        //        CGContextSetBlendMode(imageContext, kCGBlendModeCopy); // From Technical Q&A QA1708: http://developer.apple.com/library/ios/#qa/qa1708/_index.html
        //使用Core Graph绘制
        CGContextDrawImage(imageContext, CGRectMake(0.0, 0.0, pixelSizeToUseForTexture.width, pixelSizeToUseForTexture.height), newImageSource);
        //所有的REF结尾的如果不需要，就需要释放
        CGContextRelease(imageContext);
        CGColorSpaceRelease(genericRGBColorspace);
		isLitteEndian = YES;
		alphaFirst = YES;
		premultiplied = YES;
    }
    else
    {
        // Access the raw image bytes directly
        //如果满足格式，可以直接访问
        dataFromImageDataProvider = CGDataProviderCopyData(CGImageGetDataProvider(newImageSource));
        imageData = (GLubyte *)CFDataGetBytePtr(dataFromImageDataProvider);
    }
	
	if (removePremultiplication && premultiplied) {
		NSUInteger	totalNumberOfPixels = round(pixelSizeToUseForTexture.width * pixelSizeToUseForTexture.height);
		uint32_t	*pixelP = (uint32_t *)imageData;
		uint32_t	pixel;
		CGFloat		srcR, srcG, srcB, srcA;

		for (NSUInteger idx=0; idx<totalNumberOfPixels; idx++, pixelP++) {
			pixel = isLitteEndian ? CFSwapInt32LittleToHost(*pixelP) : CFSwapInt32BigToHost(*pixelP);

			if (alphaFirst) {
				srcA = (CGFloat)((pixel & 0xff000000) >> 24) / 255.0f;
			}
			else {
				srcA = (CGFloat)(pixel & 0x000000ff) / 255.0f;
				pixel >>= 8;
			}

			srcR = (CGFloat)((pixel & 0x00ff0000) >> 16) / 255.0f;
			srcG = (CGFloat)((pixel & 0x0000ff00) >> 8) / 255.0f;
			srcB = (CGFloat)(pixel & 0x000000ff) / 255.0f;

			//计算各个通道与Alpha通道的比例
			srcR /= srcA; srcG /= srcA; srcB /= srcA;

			//再还原各个通道的值
			pixel = (uint32_t)(srcR * 255.0) << 16;
			pixel |= (uint32_t)(srcG * 255.0) << 8;
			pixel |= (uint32_t)(srcB * 255.0);

			if (alphaFirst) {
				pixel |= (uint32_t)(srcA * 255.0) << 24;
			}
			else {
				pixel <<= 8;
				pixel |= (uint32_t)(srcA * 255.0);
			}
			*pixelP = isLitteEndian ? CFSwapInt32HostToLittle(pixel) : CFSwapInt32HostToBig(pixel);
		}
	}
	
    //    elapsedTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0;
    //    NSLog(@"Core Graphics drawing time: %f", elapsedTime);
    
    //    CGFloat currentRedTotal = 0.0f, currentGreenTotal = 0.0f, currentBlueTotal = 0.0f, currentAlphaTotal = 0.0f;
    //	NSUInteger totalNumberOfPixels = round(pixelSizeToUseForTexture.width * pixelSizeToUseForTexture.height);
    //
    //    for (NSUInteger currentPixel = 0; currentPixel < totalNumberOfPixels; currentPixel++)
    //    {
    //        currentBlueTotal += (CGFloat)imageData[(currentPixel * 4)] / 255.0f;
    //        currentGreenTotal += (CGFloat)imageData[(currentPixel * 4) + 1] / 255.0f;
    //        currentRedTotal += (CGFloat)imageData[(currentPixel * 4 + 2)] / 255.0f;
    //        currentAlphaTotal += (CGFloat)imageData[(currentPixel * 4) + 3] / 255.0f;
    //    }
    //
    //    NSLog(@"Debug, average input image red: %f, green: %f, blue: %f, alpha: %f", currentRedTotal / (CGFloat)totalNumberOfPixels, currentGreenTotal / (CGFloat)totalNumberOfPixels, currentBlueTotal / (CGFloat)totalNumberOfPixels, currentAlphaTotal / (CGFloat)totalNumberOfPixels);
    
    runSynchronouslyOnVideoProcessingQueue(^{
        [GPUImageContext useImageProcessingContext];
        
        outputFramebuffer = [[GPUImageContext sharedFramebufferCache] fetchFramebufferForSize:pixelSizeToUseForTexture onlyTexture:YES];
        [outputFramebuffer disableReferenceCounting];

        glBindTexture(GL_TEXTURE_2D, [outputFramebuffer texture]);
        if (self.shouldSmoothlyScaleOutput)
        {
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR);
        }
        // no need to use self.outputTextureOptions here since pictures need this texture formats and type
        //绘制图片
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, (int)pixelSizeToUseForTexture.width, (int)pixelSizeToUseForTexture.height, 0, format, GL_UNSIGNED_BYTE, imageData);
        //如果需要平滑Scale
        if (self.shouldSmoothlyScaleOutput)
        {
            glGenerateMipmap(GL_TEXTURE_2D);
        }
        //将GLTextTure_2D绑定到默认的纹理上
        glBindTexture(GL_TEXTURE_2D, 0);
        //整个过程结束后，实例对应的texture已经被绘制上图像了
    });
    
    if (shouldRedrawUsingCoreGraphics)
    {
        free(imageData);
    }
    else
    {
        if (dataFromImageDataProvider)
        {
            CFRelease(dataFromImageDataProvider);
        }
    }
    
    return self;
}

// ARC forbids explicit message send of 'release'; since iOS 6 even for dispatch_release() calls: stripping it out in that case is required.
- (void)dealloc;
{
    [outputFramebuffer enableReferenceCounting];
    [outputFramebuffer unlock];

#if !OS_OBJECT_USE_OBJC
    if (imageUpdateSemaphore != NULL)
    {
        dispatch_release(imageUpdateSemaphore);
    }
#endif
}

#pragma mark -
#pragma mark Image rendering

- (void)removeAllTargets;
{
    [super removeAllTargets];
    hasProcessedImage = NO;
}

- (void)processImage;
{
    [self processImageWithCompletionHandler:nil];
}

/**
 * 赋值本实例维护的Target列表，可以对应多个GPUImageInput协议的实例
 * @param completion
 * @return
 */
- (BOOL)processImageWithCompletionHandler:(void (^)(void))completion;
{
    hasProcessedImage = YES;
    
    //    dispatch_semaphore_wait(imageUpdateSemaphore, DISPATCH_TIME_FOREVER);
    //禁止调用两次
    if (dispatch_semaphore_wait(imageUpdateSemaphore, DISPATCH_TIME_NOW) != 0)
    {
        return NO;
    }
    
    runAsynchronouslyOnVideoProcessingQueue(^{        
        for (id<GPUImageInput> currentTarget in targets)
        {
            NSInteger indexOfObject = [targets indexOfObject:currentTarget];
            //找到对应的textureIndexOfTarget
            NSInteger textureIndexOfTarget = [[targetTextureIndices objectAtIndex:indexOfObject] integerValue];
            //这个target可以是很多类型，例如filter，是一种target
            [currentTarget setCurrentlyReceivingMonochromeInput:NO];
            [currentTarget setInputSize:pixelSizeOfImage atIndex:textureIndexOfTarget];
            [currentTarget setInputFramebuffer:outputFramebuffer atIndex:textureIndexOfTarget];
            [currentTarget newFrameReadyAtTime:kCMTimeIndefinite atIndex:textureIndexOfTarget];
        }
        
        dispatch_semaphore_signal(imageUpdateSemaphore);
        
        if (completion != nil) {
            completion();
        }
    });
    
    return YES;
}

- (void)processImageUpToFilter:(GPUImageOutput<GPUImageInput> *)finalFilterInChain withCompletionHandler:(void (^)(UIImage *processedImage))block;
{
    [finalFilterInChain useNextFrameForImageCapture];
    [self processImageWithCompletionHandler:^{
        UIImage *imageFromFilter = [finalFilterInChain imageFromCurrentFramebuffer];
        block(imageFromFilter);
    }];
}

- (CGSize)outputImageSize;
{
    return pixelSizeOfImage;
}

/**
 * 添加Target
 * @param newTarget
 * @param textureLocation
 */
- (void)addTarget:(id<GPUImageInput>)newTarget atTextureLocation:(NSInteger)textureLocation;
{
    [super addTarget:newTarget atTextureLocation:textureLocation];
    
    if (hasProcessedImage)
    {
        [newTarget setInputSize:pixelSizeOfImage atIndex:textureLocation];
        [newTarget newFrameReadyAtTime:kCMTimeIndefinite atIndex:textureLocation];
    }
}

@end
