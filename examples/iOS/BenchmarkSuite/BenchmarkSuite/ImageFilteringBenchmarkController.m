#import "ImageFilteringBenchmarkController.h"
#import "GPUImage.h"

@implementation ImageFilteringBenchmarkController

#pragma mark -
#pragma mark Still image benchmarks

- (void)runBenchmark
{
    // Take in a UIImage, filter it at full resolution (2000 x 1494), and time one operation of this
    // Images are written out to disk to verify that the filter worked as expected
    //获取测试UIImage
    UIImage *inputImage = [UIImage imageNamed:@"Lambeau.jpg"];
    
    [self imageProcessedOnCPU:inputImage]; // I've disabled the writing here, because something's busted with that
    //    UIImage *imageFilteredUsingCPURoutine = [self imageProcessedOnCPU:inputImage];
    //    [self writeImage:imageFilteredUsingCPURoutine toFile:@"Lambeau-CPUFiltered.png"];

    
    // Pulling creating the Core Image context out of the benchmarking area, because it can only be created once and reused
    if (coreImageContext == nil)
    {
        coreImageContext = [CIContext contextWithOptions:nil];
    }

    UIImage *imageFilteredUsingCoreImageRoutine = [self imageProcessedUsingCoreImage:inputImage];
    [self writeImage:imageFilteredUsingCoreImageRoutine toFile:@"Lambeau-CoreImageFiltered.png"];
    
    UIImage *imageFilteredUsingGPUImageRoutine = [self imageProcessedUsingGPUImage:inputImage];
    [self writeImage:imageFilteredUsingGPUImageRoutine toFile:@"Lambeau-GPUImageFiltered.png"];
    
    [self.tableView reloadData];
}

/**
 * 使用CPU来处理图片
 * CGImage就是使用CPU来处理图片的
 * @param imageToProcess
 * @return
 */
- (UIImage *)imageProcessedOnCPU:(UIImage *)imageToProcess;
{
    // Drawn from Rahul Vyas' answer on Stack Overflow at http://stackoverflow.com/a/4211729/19679

    //获取AbsoluteTime
    CFAbsoluteTime elapsedTime, startTime = CFAbsoluteTimeGetCurrent();

    CGImageRef cgImage = [imageToProcess CGImage];  //获取core graph
    CGImageRetain(cgImage);
    //获取Bitmap数据
    CGDataProviderRef provider = CGImageGetDataProvider(cgImage);
    CFDataRef bitmapData = CGDataProviderCopyData(provider);
    //获取指针
    UInt8* data = (UInt8*)CFDataGetBytePtr(bitmapData);
    //不需要cgImage的指针？？？？指针是指针，不是原始的数据内容可能是这样
    CGImageRelease(cgImage);
    
    int width = imageToProcess.size.width;
    int height = imageToProcess.size.height;
    //获取图片的长度
    NSInteger myDataLength = width * height * 4;
    
    
    for (int i = 0; i < myDataLength; i+=4)
    {
        //获取RGB像素
        UInt8 r_pixel = data[i];
        UInt8 g_pixel = data[i+1];
        UInt8 b_pixel = data[i+2];

        //计算
        int outputRed = (r_pixel * .393) + (g_pixel *.769) + (b_pixel * .189);
        int outputGreen = (r_pixel * .349) + (g_pixel *.686) + (b_pixel * .168);
        int outputBlue = (r_pixel * .272) + (g_pixel *.534) + (b_pixel * .131);
        
        if(outputRed>255)outputRed=255;
        if(outputGreen>255)outputGreen=255;
        if(outputBlue>255)outputBlue=255;
        
        
        data[i] = outputRed;
        data[i+1] = outputGreen;
        data[i+2] = outputBlue;
    }

    //准备拷贝图片
    CGDataProviderRef provider2 = CGDataProviderCreateWithData(NULL, data, myDataLength, NULL);
    //拷贝图片的属性
    int bitsPerComponent = 8;
    int bitsPerPixel = 32;
    int bytesPerRow = 4 * width;
    //颜色空间
    CGColorSpaceRef colorSpaceRef = CGColorSpaceCreateDeviceRGB();
    //顺序
    CGBitmapInfo bitmapInfo = kCGBitmapByteOrderDefault;
    //Rendering模式
    CGColorRenderingIntent renderingIntent = kCGRenderingIntentDefault;
    //创建CGImage
    CGImageRef imageRef =
            CGImageCreate(width, height, bitsPerComponent,
                    bitsPerPixel, bytesPerRow, colorSpaceRef, bitmapInfo, provider2, NULL, NO, renderingIntent);

    //所有的REF都需要Release
    CGColorSpaceRelease(colorSpaceRef);
    CGDataProviderRelease(provider2);
    CFRelease(bitmapData);

    //由CGImageRef转换为UIImage
    UIImage *sepiaImage = [UIImage imageWithCGImage:imageRef];
    CGImageRelease(imageRef);
    
    elapsedTime = CFAbsoluteTimeGetCurrent() - startTime;
    processingTimeForCPURoutine = elapsedTime * 1000.0;
    //获得时间
    return sepiaImage;
}

/**
 * 使用CIImage runImage操作
 * @param imageToProcess
 * @return
 */
- (UIImage *)imageProcessedUsingCoreImage:(UIImage *)imageToProcess;
{
    /*
    NSArray *filterNames = [CIFilter filterNamesInCategory:kCICategoryBuiltIn];
    
    NSLog(@"Built in filters");
    for (NSString *currentFilterName in filterNames)
    {
        NSLog(@"%@", currentFilterName);
    }
    */
    
    CFAbsoluteTime elapsedTime, startTime = CFAbsoluteTimeGetCurrent();

    //获取CIImage
    CIImage *inputImage = [[CIImage alloc] initWithCGImage:imageToProcess.CGImage];

    //获取CIFilter
    CIFilter *sepiaTone = [CIFilter filterWithName:@"CISepiaTone"
                                     keysAndValues: kCIInputImageKey, inputImage, 
                           @"inputIntensity", [NSNumber numberWithFloat:1.0], nil];

    //输出CIImage
    CIImage *result = [sepiaTone outputImage];
    
//    UIImage *resultImage = [UIImage imageWithCIImage:result]; // This gives a nil image, because it doesn't render, unless I'm doing something wrong

    //从CIImage拷贝出CGImage
    CGImageRef resultRef = [coreImageContext createCGImage:result fromRect:CGRectMake(0, 0, imageToProcess.size.width, imageToProcess.size.height)];
    //从CGImage到UIImage
    UIImage *resultImage = [UIImage imageWithCGImage:resultRef];
    CGImageRelease(resultRef);
    elapsedTime = CFAbsoluteTimeGetCurrent() - startTime;
    processingTimeForCoreImageRoutine = elapsedTime * 1000.0;
    
    return resultImage;
}

/**
 * 使用GPU来处理图片
 * @param imageToProcess
 * @return
 */
- (UIImage *)imageProcessedUsingGPUImage:(UIImage *)imageToProcess;
{
    CFAbsoluteTime elapsedTime, startTime = CFAbsoluteTimeGetCurrent();

    //GPUImagePicture 继承于GPUImageOutput，此实例维护了一系列的GPUImageinput协议，每一个GPUImageInput都维护了一个texture
    GPUImagePicture *stillImageSource = [[GPUImagePicture alloc] initWithImage:imageToProcess];
    GPUImageSepiaFilter *stillImageFilter = [[GPUImageSepiaFilter alloc] init];
    
    [stillImageSource addTarget:stillImageFilter];
    [stillImageFilter useNextFrameForImageCapture];
    [stillImageSource processImage];
    
    UIImage *currentFilteredVideoFrame = [stillImageFilter imageFromCurrentFramebuffer];
    
    elapsedTime = CFAbsoluteTimeGetCurrent() - startTime;
    processingTimeForGPUImageRoutine = elapsedTime * 1000.0;
    
    return currentFilteredVideoFrame;
}

- (void)writeImage:(UIImage *)imageToWrite toFile:(NSString *)fileName;
{
    if (imageToWrite == nil)
    {
        return;
    }
    
    NSData *dataForPNGFile = UIImagePNGRepresentation(imageToWrite);
    
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    
    NSError *error = nil;
    if (![dataForPNGFile writeToFile:[documentsDirectory stringByAppendingPathComponent:fileName] options:NSAtomicWrite error:&error])
    {
        return;
    }
}

@end
