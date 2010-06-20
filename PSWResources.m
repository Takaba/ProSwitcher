#import "PSWResources.h"

#import <CoreGraphics/CoreGraphics.h>
#import <CaptainHook/CaptainHook.h>

#include <sys/types.h>
#include <sys/sysctl.h>

static NSMutableDictionary *imageCache;
static NSBundle *sharedBundle;
static NSBundle *localizationBundle;

UIImage *PSWGetCachedImageResource(NSString *name, NSBundle *bundle)
{
	NSString *key = [NSString stringWithFormat:@"%@#%@", [bundle bundlePath], name];
	UIImage *result = [imageCache objectForKey:key];
	if (!result) {
		if (!imageCache)
			imageCache = [[NSMutableDictionary alloc] init];
		result = [UIImage imageWithContentsOfFile:[bundle pathForResource:name ofType:@"png"]];
		if (result) {
			if (imageCache)
				[imageCache setObject:result forKey:key];
			else
				imageCache = [[NSMutableDictionary alloc] initWithObjectsAndKeys:result, key, nil];
		}
	}
	return result;
}

UIImage *PSWGetScaledCachedImageResource(NSString *name, NSBundle *bundle, CGSize size)
{
	// Search for cached image
	NSString *key = [NSString stringWithFormat:@"%@#%@#%@", [bundle bundlePath], name, NSStringFromCGSize(size)];
	UIImage *image = [imageCache objectForKey:key];
	if (image)
		return image;
	// Get unscaled image and check if is already the right size
	image = PSWGetCachedImageResource(name, bundle);
	if (!image)
		return image;
	CGSize unscaledSize = [image size];
	if (unscaledSize.width == size.width && unscaledSize.height == size.height)
		return image;
	// Create a bitmap context that mimics the format of the source context
	CGImageRef cgImage = [image CGImage];
	CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
	CGContextRef context = CGBitmapContextCreate(NULL, (size_t)size.width, (size_t)size.height, 8, 4 * (size_t)size.width, colorSpace, kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
	CGColorSpaceRelease(colorSpace);
	// Setup transformation
	CGContextSetInterpolationQuality(context, kCGInterpolationNone);
	CGContextTranslateCTM(context, 0.0f, size.height); 
	CGContextScaleCTM(context, 1.0f, -1.0f);
	// Draw stretchable image
	UIGraphicsPushContext(context);
	[[image stretchableImageWithLeftCapWidth:((NSInteger)unscaledSize.width)/2 topCapHeight:((NSInteger)unscaledSize.height)/2] drawInRect:CGRectMake(0.0f, 0.0f, size.width, size.height)];
	UIGraphicsPopContext();
	// Create CGImage
	CGContextFlush(context);
	cgImage = CGBitmapContextCreateImage(context);
	CGContextRelease(context);
	// Create UIImage
	image = [UIImage imageWithCGImage:cgImage];
	CGImageRelease(cgImage);
	// Update cache
	[imageCache setObject:image forKey:key];
	return image;
}

UIImage *PSWImage(NSString *name)
{
	return PSWGetCachedImageResource(name, sharedBundle);
}

UIImage *PSWScaledImage(NSString *name, CGSize size)
{
	return PSWGetScaledCachedImageResource(name, sharedBundle, size);
}


static void ClipContextRounded(CGContextRef c, CGSize size, CGFloat cornerRadius)
{
	CGSize half;
	half.width = size.width * 0.5f;
	half.height = size.height * 0.5f;
	CGContextMoveToPoint(c, size.width, half.height);
	CGContextAddArcToPoint(c, size.width, size.height, half.width, size.height, cornerRadius);
	CGContextAddArcToPoint(c, 0.0f, size.height, 0.0f, half.height, cornerRadius);
	CGContextAddArcToPoint(c, 0.0f, 0.0f, half.width, 0.0f, cornerRadius);
	CGContextAddArcToPoint(c, size.width, 0.0f, size.width, half.height, cornerRadius);
	CGContextClosePath(c);
	CGContextClip(c);
}

UIImage *PSWGetCachedCornerMaskOfSize(CGSize size, CGFloat cornerRadius)
{
	if (size.width < 1.0f || size.height < 1.0f)
		return nil;
	NSString *key = [NSString stringWithFormat:@"%fx%f-%f", size.width, size.height, cornerRadius];
	UIImage *result = [imageCache objectForKey:key];
	if (!result) {
		CGContextRef c;
		// Only iPad supports using mask images as layer masks (older models require full images, then use only the alpha channel)
		if (PSWGetHardwareType() >= PSWHardwareTypeiPad1G)
			c = CGBitmapContextCreate(NULL, (size_t)size.width, (size_t)size.height, 8, (size_t)size.width, NULL, kCGImageAlphaOnly);
		else {
			CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
			c = CGBitmapContextCreate(NULL, (size_t)size.width, (size_t)size.height, 8, (size_t)size.width * 4, colorSpace, kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
			CGColorSpaceRelease(colorSpace);
		}
		CGRect rect;
		rect.origin.x = 0.0f;
		rect.origin.y = 0.0f;
		rect.size = size;
		if (cornerRadius > 0.0f)
			ClipContextRounded(c, size, cornerRadius);
		CGContextSetRGBFillColor(c, 1.0f, 1.0f, 1.0f, 1.0f);
		CGContextFillRect(c, rect);
		CGImageRef image = CGBitmapContextCreateImage(c);
		CGContextRelease(c);
		result = [UIImage imageWithCGImage:image];
		CGImageRelease(image);
		if (imageCache)
			[imageCache setObject:result forKey:key];
		else
			imageCache = [[NSMutableDictionary alloc] initWithObjectsAndKeys:result, key, nil];
	}
	return result;
}

void PSWClearResourceCache()
{
	[imageCache release];
	imageCache = nil;
}

NSString *PSWLocalize(NSString *text)
{
	return [localizationBundle localizedStringForKey:text value:nil table:nil];
}

PSWHardwareType PSWGetHardwareType()
{
	size_t size;
	sysctlbyname("hw.machine", NULL, &size, NULL, 0);
	char machine[size];
	if (strcmp(machine, "iPhone1,1") == 0)
		return PSWHardwareTypeiPhoneOriginal;
	if (strcmp(machine, "iPod1,1") == 0)
		return PSWHardwareTypeiPodTouch1G;
	if (strcmp(machine, "iPhone1,2") == 0)
		return PSWHardwareTypeiPhone3G;
	if (strcmp(machine, "iPod2,1") == 0)
		return PSWHardwareTypeiPodTouch2G;
	if (strcmp(machine, "iPhone2,1") == 0)
		return PSWHardwareTypeiPhone3GS;
	if (strcmp(machine, "iPod3,1") == 0)
		return PSWHardwareTypeiPodTouch3G;
	if (strcmp(machine, "iPad1,1") == 0)
		return PSWHardwareTypeiPad1G;
	return PSWHardwareTypeUnknown;
}

CHConstructor
{
	CHAutoreleasePoolForScope();
	sharedBundle = [[NSBundle bundleWithPath:@"/Applications/ProSwitcher.app"] retain];
	localizationBundle = [[NSBundle bundleWithPath:@"/Library/PreferenceLoader/Preferences/ProSwitcher"] retain];
}