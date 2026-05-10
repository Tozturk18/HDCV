#import <AppKit/AppKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#include "hdcv_analysis.h"

#include <math.h>
#include <string.h>

typedef NS_ENUM(NSInteger, HDCVTimeAxisMode) {
    HDCVTimeAxisModeSequence = 0,
    HDCVTimeAxisModeExperiment = 1,
};

typedef NS_ENUM(NSInteger, HDCVLinePlotInteractionMode) {
    HDCVLinePlotInteractionModeNone = 0,
    HDCVLinePlotInteractionModeSelectX = 1,
};

@class HDCVDropHostView;
@class HDCVHeatmapView;
@class HDCVLinePlotView;

@protocol HDCVDropHostViewDelegate <NSObject>
- (void)dropHostView:(HDCVDropHostView *)view didReceiveFilePath:(NSString *)filePath;
@end

@protocol HDCVHeatmapViewDelegate <NSObject>
- (void)heatmapView:(HDCVHeatmapView *)view didSelectScanIndex:(NSUInteger)scanIndex pointIndex:(NSUInteger)pointIndex;
@end

@protocol HDCVLinePlotDataSource <NSObject>
- (NSUInteger)sampleCountForLinePlotView:(HDCVLinePlotView *)view;
- (double)linePlotView:(HDCVLinePlotView *)view xValueAtIndex:(NSUInteger)index;
- (double)linePlotView:(HDCVLinePlotView *)view yValueAtIndex:(NSUInteger)index;
@end

@protocol HDCVLinePlotViewDelegate <NSObject>
- (void)linePlotView:(HDCVLinePlotView *)view didSelectXValue:(double)xValue;
@end

@interface HDCVDropHostView : NSView <NSDraggingDestination>
@property(nonatomic, weak) id<HDCVDropHostViewDelegate> delegate;
@property(nonatomic) BOOL dragHighlight;
@end

@interface HDCVHeatmapView : NSView
@property(nonatomic, strong) NSImage *image;
@property(nonatomic, strong) NSData *voltageData;
@property(nonatomic, weak) id<HDCVHeatmapViewDelegate> delegate;
@property(nonatomic, copy) NSArray<NSString *> *xTickLabels;
@property(nonatomic, copy) NSArray<NSNumber *> *xTickFractions;
@property(nonatomic) NSUInteger selectedScanIndex;
@property(nonatomic) NSUInteger backgroundScanIndex;
@property(nonatomic) NSUInteger scanCount;
@property(nonatomic) NSUInteger selectedPointIndex;
@property(nonatomic) NSUInteger pointCount;
@property(nonatomic, copy) NSString *titleText;
@property(nonatomic, copy) NSString *subtitleText;
@end

@interface HDCVLinePlotView : NSView
@property(nonatomic, weak) id<HDCVLinePlotDataSource> dataSource;
@property(nonatomic, weak) id<HDCVLinePlotViewDelegate> delegate;
@property(nonatomic) HDCVLinePlotInteractionMode interactionMode;
@property(nonatomic, copy) NSString *titleText;
@property(nonatomic, copy) NSString *subtitleText;
@property(nonatomic, copy) NSString *xLabelText;
@property(nonatomic, copy) NSString *yLabelText;
@property(nonatomic, copy) NSString *xTickFormat;
@property(nonatomic, copy) NSString *yTickFormat;
@property(nonatomic, strong) NSColor *strokeColor;
@property(nonatomic) double xMin;
@property(nonatomic) double xMax;
@property(nonatomic) double yMin;
@property(nonatomic) double yMax;
@property(nonatomic) double selectedXValue;
@property(nonatomic) double selectedYValue;
@property(nonatomic) double baselineYValue;
@property(nonatomic) BOOL showsSelection;
@property(nonatomic) BOOL showsBaseline;
@end

@interface HDCVLoadedFile : NSObject
- (instancetype)initWithPath:(NSString *)path maxOverviewColumns:(NSUInteger)maxOverviewColumns error:(NSError **)error;
- (uint32_t)scanCount;
- (uint32_t)pointsPerScan;
- (uint32_t)overviewColumnCount;
- (float)overviewMinValue;
- (float)overviewMaxValue;
- (double)sampleRateHz;
- (double)cvfHz;
- (double)scanIntervalSeconds;
- (double)scanDurationSeconds;
- (uint32_t)runCount;
- (uint32_t)scansPerRun;
- (BOOL)hasExperimentTiming;
- (double)runDurationSeconds;
- (double)delayBetweenRunsSeconds;
- (float)voltageAtPoint:(NSUInteger)pointIndex;
- (double)withinScanTimeSecondsAtPoint:(NSUInteger)pointIndex;
- (double)sequenceTimeSecondsAtScan:(NSUInteger)scanIndex;
- (double)experimentTimeSecondsAtScan:(NSUInteger)scanIndex;
- (NSData *)voltageData;
- (NSData *)overviewData;
- (NSString *)summaryAndMetadataText;
- (BOOL)copyScanAtIndex:(uint32_t)scanIndex intoMutableData:(NSMutableData *)buffer min:(float *)outMin max:(float *)outMax;
- (BOOL)copyPointTraceAtIndex:(uint32_t)pointIndex intoMutableData:(NSMutableData *)buffer min:(float *)outMin max:(float *)outMax;
@end

@interface HDCVViewerController : NSObject <NSApplicationDelegate, HDCVDropHostViewDelegate, HDCVHeatmapViewDelegate, HDCVLinePlotDataSource, HDCVLinePlotViewDelegate>
- (void)setInitialPathFromArguments:(NSArray<NSString *> *)arguments;
@end

static NSString *const HDCVViewerErrorDomain = @"com.openai.hdcvviewer";

static NSColor *HDCVCanvasColor(void)
{
    return [NSColor colorWithRed:0.94 green:0.955 blue:0.972 alpha:1.0];
}

static NSColor *HDCVCardColor(void)
{
    return [NSColor colorWithRed:0.985 green:0.988 blue:0.994 alpha:1.0];
}

static NSColor *HDCVCardBorderColor(void)
{
    return [NSColor colorWithRed:0.84 green:0.875 blue:0.92 alpha:1.0];
}

static NSColor *HDCVHeroColor(void)
{
    return [NSColor colorWithRed:0.07 green:0.16 blue:0.27 alpha:1.0];
}

static NSColor *HDCVHeroBorderColor(void)
{
    return [NSColor colorWithRed:0.20 green:0.35 blue:0.52 alpha:1.0];
}

static NSColor *HDCVAccentBlue(void)
{
    return [NSColor colorWithRed:0.10 green:0.36 blue:0.70 alpha:1.0];
}

static NSColor *HDCVAccentTeal(void)
{
    return [NSColor colorWithRed:0.07 green:0.49 blue:0.46 alpha:1.0];
}

static NSColor *HDCVAccentCopper(void)
{
    return [NSColor colorWithRed:0.82 green:0.39 blue:0.15 alpha:1.0];
}

static NSColor *HDCVAccentCrimson(void)
{
    return [NSColor colorWithRed:0.72 green:0.18 blue:0.18 alpha:1.0];
}

static NSColor *HDCVMutedText(void)
{
    return [NSColor colorWithRed:0.33 green:0.38 blue:0.44 alpha:1.0];
}

static NSColor *HDCVSoftGridColor(void)
{
    return [NSColor colorWithWhite:0.88 alpha:1.0];
}

static NSView *HDCVPanelContainer(void)
{
    NSView *view = [[NSView alloc] initWithFrame:NSZeroRect];
    view.translatesAutoresizingMaskIntoConstraints = NO;
    view.wantsLayer = YES;
    view.layer.backgroundColor = HDCVCardColor().CGColor;
    view.layer.borderColor = HDCVCardBorderColor().CGColor;
    view.layer.borderWidth = 1.0;
    view.layer.cornerRadius = 16.0;
    return view;
}

static NSTextField *HDCVLabel(NSString *string, NSFont *font, NSColor *color)
{
    NSTextField *label = [NSTextField labelWithString:string];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = font;
    label.textColor = color;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    return label;
}

static NSString *HDCVSafeStringFromBytes(const char *bytes, size_t length)
{
    NSString *string;
    NSData *data;

    if (bytes == NULL || length == 0U) {
        return @"";
    }

    data = [NSData dataWithBytes:bytes length:length];
    string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (string == nil) {
        string = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
    }
    if (string == nil) {
        string = [[NSString alloc] initWithData:data encoding:NSWindowsCP1252StringEncoding];
    }
    return (string != nil) ? string : @"";
}

static void HDCVExpandRange(double *minValue, double *maxValue)
{
    double range = *maxValue - *minValue;
    if (range < 1.0e-9) {
        double center = (*maxValue + *minValue) * 0.5;
        *minValue = center - 1.0;
        *maxValue = center + 1.0;
    } else {
        double padding = range * 0.06;
        *minValue -= padding;
        *maxValue += padding;
    }
}

@implementation HDCVDropHostView

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self != nil) {
        self.wantsLayer = YES;
        [self registerForDraggedTypes:@[NSPasteboardTypeFileURL]];
    }
    return self;
}

- (BOOL)isFlipped
{
    return YES;
}

- (BOOL)acceptsFirstResponder
{
    return YES;
}

- (NSString *)firstDraggedFilePathFromPasteboard:(NSPasteboard *)pasteboard
{
    NSArray<NSURL *> *urls = [pasteboard readObjectsForClasses:@[[NSURL class]]
                                                       options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}];
    for (NSURL *url in urls) {
        if (url.isFileURL) {
            return url.path;
        }
    }
    return nil;
}

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender
{
    NSString *filePath = [self firstDraggedFilePathFromPasteboard:sender.draggingPasteboard];
    self.dragHighlight = (filePath != nil);
    [self setNeedsDisplay:YES];
    return (filePath != nil) ? NSDragOperationCopy : NSDragOperationNone;
}

- (void)draggingExited:(id<NSDraggingInfo>)sender
{
    (void)sender;
    self.dragHighlight = NO;
    [self setNeedsDisplay:YES];
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender
{
    NSString *filePath = [self firstDraggedFilePathFromPasteboard:sender.draggingPasteboard];
    self.dragHighlight = NO;
    [self setNeedsDisplay:YES];
    if (filePath == nil) {
        return NO;
    }
    [self.delegate dropHostView:self didReceiveFilePath:filePath];
    return YES;
}

- (void)drawRect:(NSRect)dirtyRect
{
    (void)dirtyRect;
    [HDCVCanvasColor() setFill];
    NSRectFill(self.bounds);

    if (self.dragHighlight) {
        NSRect borderRect = NSInsetRect(self.bounds, 10.0, 10.0);
        NSBezierPath *border = [NSBezierPath bezierPathWithRoundedRect:borderRect xRadius:18.0 yRadius:18.0];
        border.lineWidth = 2.0;
        CGFloat dashes[] = {9.0, 7.0};
        [border setLineDash:dashes count:2 phase:0.0];
        [[HDCVAccentBlue() colorWithAlphaComponent:0.65] setStroke];
        [border stroke];
    }
}

@end

@implementation HDCVHeatmapView

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self != nil) {
        _titleText = @"Color Plot";
        _subtitleText = @"Raw Current";
        _backgroundScanIndex = NSNotFound;
        self.wantsLayer = YES;
        self.layer.backgroundColor = NSColor.whiteColor.CGColor;
    }
    return self;
}

- (BOOL)isFlipped
{
    return YES;
}

- (NSRect)plotRect
{
    return NSMakeRect(66.0, 46.0, MAX(40.0, self.bounds.size.width - 90.0), MAX(40.0, self.bounds.size.height - 82.0));
}

- (NSDictionary<NSAttributedStringKey, id> *)labelAttributesWithColor:(NSColor *)color size:(CGFloat)size weight:(NSFontWeight)weight
{
    return @{
        NSFontAttributeName: [NSFont systemFontOfSize:size weight:weight],
        NSForegroundColorAttributeName: color
    };
}

- (void)setImage:(NSImage *)image
{
    _image = image;
    [self setNeedsDisplay:YES];
}

- (void)setSelectedScanIndex:(NSUInteger)selectedScanIndex
{
    _selectedScanIndex = selectedScanIndex;
    [self setNeedsDisplay:YES];
}

- (void)setBackgroundScanIndex:(NSUInteger)backgroundScanIndex
{
    _backgroundScanIndex = backgroundScanIndex;
    [self setNeedsDisplay:YES];
}

- (void)setSelectedPointIndex:(NSUInteger)selectedPointIndex
{
    _selectedPointIndex = selectedPointIndex;
    [self setNeedsDisplay:YES];
}

- (void)setXTickLabels:(NSArray<NSString *> *)xTickLabels
{
    _xTickLabels = [xTickLabels copy];
    [self setNeedsDisplay:YES];
}

- (void)setXTickFractions:(NSArray<NSNumber *> *)xTickFractions
{
    _xTickFractions = [xTickFractions copy];
    [self setNeedsDisplay:YES];
}

- (void)setSubtitleText:(NSString *)subtitleText
{
    _subtitleText = [subtitleText copy];
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect
{
    NSRect plotRect = [self plotRect];
    NSDictionary *titleAttrs = [self labelAttributesWithColor:NSColor.blackColor size:14.0 weight:NSFontWeightSemibold];
    NSDictionary *subtitleAttrs = [self labelAttributesWithColor:HDCVMutedText() size:10.5 weight:NSFontWeightMedium];
    NSDictionary *axisAttrs = [self labelAttributesWithColor:HDCVMutedText() size:10.0 weight:NSFontWeightRegular];
    NSDictionary *tickAttrs = [self labelAttributesWithColor:HDCVMutedText() size:9.0 weight:NSFontWeightRegular];

    (void)dirtyRect;
    [NSColor.whiteColor setFill];
    NSRectFill(self.bounds);

    [[NSColor colorWithWhite:0.955 alpha:1.0] setFill];
    NSRectFill(plotRect);

    [[NSColor colorWithWhite:0.84 alpha:1.0] setStroke];
    NSBezierPath *border = [NSBezierPath bezierPathWithRoundedRect:plotRect xRadius:10.0 yRadius:10.0];
    border.lineWidth = 1.0;
    [border stroke];

    [self.titleText drawAtPoint:NSMakePoint(plotRect.origin.x, 10.0) withAttributes:titleAttrs];
    [self.subtitleText drawAtPoint:NSMakePoint(plotRect.origin.x, 28.0) withAttributes:subtitleAttrs];

    if (self.image != nil) {
        [self.image drawInRect:plotRect];
    }

    if (self.scanCount > 0U && self.backgroundScanIndex != NSNotFound && self.backgroundScanIndex < self.scanCount) {
        CGFloat backgroundFraction = self.scanCount > 1U ? (CGFloat)self.backgroundScanIndex / (CGFloat)(self.scanCount - 1U) : 0.0;
        CGFloat backgroundX = plotRect.origin.x + (backgroundFraction * plotRect.size.width);
        NSBezierPath *backgroundLine = [NSBezierPath bezierPath];
        [backgroundLine moveToPoint:NSMakePoint(backgroundX, plotRect.origin.y)];
        [backgroundLine lineToPoint:NSMakePoint(backgroundX, NSMaxY(plotRect))];
        backgroundLine.lineWidth = 1.2;
        CGFloat dashes[] = {3.0, 4.0};
        [backgroundLine setLineDash:dashes count:2 phase:0.0];
        [[HDCVAccentBlue() colorWithAlphaComponent:0.95] setStroke];
        [backgroundLine stroke];
    }

    if (self.scanCount > 0U && self.pointCount > 0U) {
        CGFloat xFraction = self.scanCount > 1U ? (CGFloat)self.selectedScanIndex / (CGFloat)(self.scanCount - 1U) : 0.0;
        CGFloat yFraction = self.pointCount > 1U ? (CGFloat)self.selectedPointIndex / (CGFloat)(self.pointCount - 1U) : 0.0;
        CGFloat crossX = plotRect.origin.x + (xFraction * plotRect.size.width);
        CGFloat crossY = plotRect.origin.y + plotRect.size.height - (yFraction * plotRect.size.height);

        NSBezierPath *vertical = [NSBezierPath bezierPath];
        [vertical moveToPoint:NSMakePoint(crossX, plotRect.origin.y)];
        [vertical lineToPoint:NSMakePoint(crossX, NSMaxY(plotRect))];
        vertical.lineWidth = 1.6;
        CGFloat verticalDashes[] = {7.0, 5.0};
        [vertical setLineDash:verticalDashes count:2 phase:0.0];
        [[HDCVAccentCrimson() colorWithAlphaComponent:0.95] setStroke];
        [vertical stroke];

        NSBezierPath *horizontal = [NSBezierPath bezierPath];
        [horizontal moveToPoint:NSMakePoint(plotRect.origin.x, crossY)];
        [horizontal lineToPoint:NSMakePoint(NSMaxX(plotRect), crossY)];
        horizontal.lineWidth = 1.4;
        CGFloat horizontalDashes[] = {6.0, 4.0};
        [horizontal setLineDash:horizontalDashes count:2 phase:0.0];
        [[HDCVAccentTeal() colorWithAlphaComponent:0.92] setStroke];
        [horizontal stroke];
    }

    [@"Time" drawAtPoint:NSMakePoint(NSMidX(plotRect) - 14.0, NSMaxY(plotRect) + 8.0) withAttributes:axisAttrs];
    [@"Voltage / Waveform Point" drawAtPoint:NSMakePoint(8.0, 16.0) withAttributes:axisAttrs];

    if (self.xTickLabels.count == self.xTickFractions.count) {
        for (NSUInteger i = 0U; i < self.xTickLabels.count; ++i) {
            CGFloat fraction = self.xTickFractions[i].doubleValue;
            NSString *label = self.xTickLabels[i];
            NSSize size = [label sizeWithAttributes:tickAttrs];
            CGFloat x = plotRect.origin.x + (fraction * plotRect.size.width) - (size.width * 0.5);
            CGFloat y = NSMaxY(plotRect) + 20.0;
            [label drawAtPoint:NSMakePoint(x, y) withAttributes:tickAttrs];
        }
    }

    if (self.voltageData.length >= self.pointCount * sizeof(float) && self.pointCount > 0U) {
        const float *voltage = self.voltageData.bytes;
        NSUInteger tickCount = MIN((NSUInteger)6U, self.pointCount);
        for (NSUInteger i = 0U; i < tickCount; ++i) {
            NSUInteger pointIndex = (tickCount == 1U)
                ? 0U
                : (NSUInteger)llround((double)i * (double)(self.pointCount - 1U) / (double)(tickCount - 1U));
            CGFloat fraction = self.pointCount > 1U ? (CGFloat)pointIndex / (CGFloat)(self.pointCount - 1U) : 0.0;
            CGFloat y = plotRect.origin.y + plotRect.size.height - (fraction * plotRect.size.height);
            NSString *label = [NSString stringWithFormat:@"%.2f V", voltage[pointIndex]];
            NSSize size = [label sizeWithAttributes:tickAttrs];
            [label drawAtPoint:NSMakePoint(6.0, y - size.height * 0.5) withAttributes:tickAttrs];

            NSBezierPath *grid = [NSBezierPath bezierPath];
            [grid moveToPoint:NSMakePoint(plotRect.origin.x, y)];
            [grid lineToPoint:NSMakePoint(NSMaxX(plotRect), y)];
            grid.lineWidth = 0.5;
            [HDCVSoftGridColor() setStroke];
            [grid stroke];
        }
    }
}

- (void)updateSelectionFromEvent:(NSEvent *)event
{
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSRect plotRect = [self plotRect];
    if (!NSPointInRect(point, plotRect) || self.scanCount == 0U || self.pointCount == 0U) {
        return;
    }

    CGFloat xFraction = (point.x - plotRect.origin.x) / plotRect.size.width;
    CGFloat yFraction = 1.0 - ((point.y - plotRect.origin.y) / plotRect.size.height);
    NSUInteger scanIndex = (NSUInteger)llround(MAX(0.0, MIN(1.0, xFraction)) * (double)(self.scanCount - 1U));
    NSUInteger pointIndex = (NSUInteger)llround(MAX(0.0, MIN(1.0, yFraction)) * (double)(self.pointCount - 1U));
    [self.delegate heatmapView:self didSelectScanIndex:scanIndex pointIndex:pointIndex];
}

- (void)mouseDown:(NSEvent *)event
{
    [self updateSelectionFromEvent:event];
}

- (void)mouseDragged:(NSEvent *)event
{
    [self updateSelectionFromEvent:event];
}

@end

@implementation HDCVLinePlotView

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self != nil) {
        _strokeColor = HDCVAccentBlue();
        _titleText = @"Plot";
        _subtitleText = @"";
        _xLabelText = @"X";
        _yLabelText = @"Y";
        _xTickFormat = @"%.2f";
        _yTickFormat = @"%.2f";
        self.wantsLayer = YES;
        self.layer.backgroundColor = NSColor.whiteColor.CGColor;
    }
    return self;
}

- (BOOL)isFlipped
{
    return YES;
}

- (NSRect)plotRect
{
    return NSMakeRect(60.0, 48.0, MAX(40.0, self.bounds.size.width - 84.0), MAX(40.0, self.bounds.size.height - 84.0));
}

- (NSDictionary<NSAttributedStringKey, id> *)labelAttributesWithColor:(NSColor *)color size:(CGFloat)size weight:(NSFontWeight)weight
{
    return @{
        NSFontAttributeName: [NSFont systemFontOfSize:size weight:weight],
        NSForegroundColorAttributeName: color
    };
}

- (double)clampedXValueForPoint:(NSPoint)point
{
    NSRect plotRect = [self plotRect];
    double fraction = (double)((point.x - plotRect.origin.x) / plotRect.size.width);
    double clampedFraction = MAX(0.0, MIN(1.0, fraction));
    return self.xMin + ((self.xMax - self.xMin) * clampedFraction);
}

- (void)drawRect:(NSRect)dirtyRect
{
    NSRect plotRect = [self plotRect];
    NSUInteger sampleCount = [self.dataSource sampleCountForLinePlotView:self];
    NSDictionary *titleAttrs = [self labelAttributesWithColor:NSColor.blackColor size:14.0 weight:NSFontWeightSemibold];
    NSDictionary *subtitleAttrs = [self labelAttributesWithColor:HDCVMutedText() size:10.5 weight:NSFontWeightMedium];
    NSDictionary *axisAttrs = [self labelAttributesWithColor:HDCVMutedText() size:10.0 weight:NSFontWeightRegular];
    NSDictionary *tickAttrs = [self labelAttributesWithColor:HDCVMutedText() size:9.0 weight:NSFontWeightRegular];
    double xMin = self.xMin;
    double xMax = self.xMax;
    double yMin = self.yMin;
    double yMax = self.yMax;
    double xRange;
    double yRange;

    (void)dirtyRect;
    [NSColor.whiteColor setFill];
    NSRectFill(self.bounds);

    [[NSColor colorWithWhite:0.955 alpha:1.0] setFill];
    NSRectFill(plotRect);

    [[NSColor colorWithWhite:0.84 alpha:1.0] setStroke];
    NSBezierPath *border = [NSBezierPath bezierPathWithRoundedRect:plotRect xRadius:10.0 yRadius:10.0];
    border.lineWidth = 1.0;
    [border stroke];

    [self.titleText drawAtPoint:NSMakePoint(plotRect.origin.x, 10.0) withAttributes:titleAttrs];
    if (self.subtitleText.length > 0U) {
        [self.subtitleText drawAtPoint:NSMakePoint(plotRect.origin.x, 28.0) withAttributes:subtitleAttrs];
    }
    [self.xLabelText drawAtPoint:NSMakePoint(NSMidX(plotRect) - 16.0, NSMaxY(plotRect) + 8.0) withAttributes:axisAttrs];
    [self.yLabelText drawAtPoint:NSMakePoint(8.0, 16.0) withAttributes:axisAttrs];

    if (sampleCount == 0U) {
        return;
    }

    if (xMax <= xMin) {
        xMax = xMin + 1.0;
    }
    if (yMax <= yMin) {
        yMax = yMin + 1.0;
    }
    xRange = xMax - xMin;
    yRange = yMax - yMin;

    for (NSUInteger tick = 0U; tick < 5U; ++tick) {
        CGFloat fraction = (CGFloat)tick / 4.0;
        double xValue = xMin + (xRange * fraction);
        double yValue = yMax - (yRange * fraction);
        NSString *xLabel = [NSString stringWithFormat:self.xTickFormat, xValue];
        NSString *yLabel = [NSString stringWithFormat:self.yTickFormat, yValue];
        NSSize xSize = [xLabel sizeWithAttributes:tickAttrs];
        NSSize ySize = [yLabel sizeWithAttributes:tickAttrs];
        CGFloat x = plotRect.origin.x + (fraction * plotRect.size.width);
        CGFloat y = plotRect.origin.y + (fraction * plotRect.size.height);

        [HDCVSoftGridColor() setStroke];
        NSBezierPath *verticalGrid = [NSBezierPath bezierPath];
        [verticalGrid moveToPoint:NSMakePoint(x, plotRect.origin.y)];
        [verticalGrid lineToPoint:NSMakePoint(x, NSMaxY(plotRect))];
        verticalGrid.lineWidth = 0.5;
        [verticalGrid stroke];

        NSBezierPath *horizontalGrid = [NSBezierPath bezierPath];
        [horizontalGrid moveToPoint:NSMakePoint(plotRect.origin.x, y)];
        [horizontalGrid lineToPoint:NSMakePoint(NSMaxX(plotRect), y)];
        horizontalGrid.lineWidth = 0.5;
        [horizontalGrid stroke];

        [xLabel drawAtPoint:NSMakePoint(x - xSize.width * 0.5, NSMaxY(plotRect) + 20.0) withAttributes:tickAttrs];
        [yLabel drawAtPoint:NSMakePoint(6.0, y - ySize.height * 0.5) withAttributes:tickAttrs];
    }

    if (self.showsBaseline) {
        double baselineFraction = (self.baselineYValue - yMin) / yRange;
        if (baselineFraction >= 0.0 && baselineFraction <= 1.0) {
            CGFloat baselineY = plotRect.origin.y + plotRect.size.height - (CGFloat)baselineFraction * plotRect.size.height;
            NSBezierPath *baseline = [NSBezierPath bezierPath];
            [baseline moveToPoint:NSMakePoint(plotRect.origin.x, baselineY)];
            [baseline lineToPoint:NSMakePoint(NSMaxX(plotRect), baselineY)];
            baseline.lineWidth = 1.0;
            CGFloat dashes[] = {4.0, 4.0};
            [baseline setLineDash:dashes count:2 phase:0.0];
            [[HDCVAccentBlue() colorWithAlphaComponent:0.50] setStroke];
            [baseline stroke];
        }
    }

    NSUInteger step = 1U;
    NSUInteger targetSegments = MAX((NSUInteger)plotRect.size.width * 2U, 1U);
    if (sampleCount > targetSegments) {
        step = sampleCount / targetSegments;
        if (step == 0U) {
            step = 1U;
        }
    }

    [self.strokeColor setStroke];
    NSBezierPath *path = [NSBezierPath bezierPath];
    path.lineWidth = 1.9;
    for (NSUInteger i = 0U; i < sampleCount; i += step) {
        double xValue = [self.dataSource linePlotView:self xValueAtIndex:i];
        double yValue = [self.dataSource linePlotView:self yValueAtIndex:i];
        CGFloat x = plotRect.origin.x + (CGFloat)((xValue - xMin) / xRange) * plotRect.size.width;
        CGFloat y = plotRect.origin.y + plotRect.size.height - (CGFloat)((yValue - yMin) / yRange) * plotRect.size.height;
        if (i == 0U) {
            [path moveToPoint:NSMakePoint(x, y)];
        } else {
            [path lineToPoint:NSMakePoint(x, y)];
        }
    }
    if ((sampleCount - 1U) % step != 0U) {
        NSUInteger i = sampleCount - 1U;
        double xValue = [self.dataSource linePlotView:self xValueAtIndex:i];
        double yValue = [self.dataSource linePlotView:self yValueAtIndex:i];
        CGFloat x = plotRect.origin.x + (CGFloat)((xValue - xMin) / xRange) * plotRect.size.width;
        CGFloat y = plotRect.origin.y + plotRect.size.height - (CGFloat)((yValue - yMin) / yRange) * plotRect.size.height;
        [path lineToPoint:NSMakePoint(x, y)];
    }
    [path stroke];

    if (self.showsSelection) {
        CGFloat selectedX = plotRect.origin.x + (CGFloat)((self.selectedXValue - xMin) / xRange) * plotRect.size.width;
        CGFloat selectedY = plotRect.origin.y + plotRect.size.height - (CGFloat)((self.selectedYValue - yMin) / yRange) * plotRect.size.height;

        NSBezierPath *vertical = [NSBezierPath bezierPath];
        [vertical moveToPoint:NSMakePoint(selectedX, plotRect.origin.y)];
        [vertical lineToPoint:NSMakePoint(selectedX, NSMaxY(plotRect))];
        vertical.lineWidth = 1.35;
        CGFloat verticalDashes[] = {6.0, 4.0};
        [vertical setLineDash:verticalDashes count:2 phase:0.0];
        [[HDCVAccentCrimson() colorWithAlphaComponent:0.96] setStroke];
        [vertical stroke];

        NSBezierPath *horizontal = [NSBezierPath bezierPath];
        [horizontal moveToPoint:NSMakePoint(plotRect.origin.x, selectedY)];
        [horizontal lineToPoint:NSMakePoint(NSMaxX(plotRect), selectedY)];
        horizontal.lineWidth = 1.15;
        CGFloat horizontalDashes[] = {5.0, 4.0};
        [horizontal setLineDash:horizontalDashes count:2 phase:0.0];
        [[HDCVAccentTeal() colorWithAlphaComponent:0.94] setStroke];
        [horizontal stroke];

        [[self.strokeColor colorWithAlphaComponent:1.0] setFill];
        NSBezierPath *marker = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(selectedX - 4.0, selectedY - 4.0, 8.0, 8.0)];
        [marker fill];
    }
}

- (void)dispatchSelectionForEvent:(NSEvent *)event
{
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSRect plotRect = [self plotRect];
    if (!NSPointInRect(point, plotRect) || self.interactionMode != HDCVLinePlotInteractionModeSelectX) {
        return;
    }
    [self.delegate linePlotView:self didSelectXValue:[self clampedXValueForPoint:point]];
}

- (void)mouseDown:(NSEvent *)event
{
    [self dispatchSelectionForEvent:event];
}

- (void)mouseDragged:(NSEvent *)event
{
    [self dispatchSelectionForEvent:event];
}

@end

@implementation HDCVLoadedFile {
    hdcv_reader _reader;
    BOOL _isOpen;
    NSData *_voltageData;
    NSData *_overviewData;
    NSString *_summaryText;
    uint32_t _overviewColumnCount;
    float _overviewMinValue;
    float _overviewMaxValue;
}

- (instancetype)initWithPath:(NSString *)path maxOverviewColumns:(NSUInteger)maxOverviewColumns error:(NSError **)error
{
    self = [super init];
    if (self == nil) {
        return nil;
    }

    if (!hdcv_reader_open(&_reader, path.fileSystemRepresentation)) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:HDCVViewerErrorDomain
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithUTF8String:_reader.error]}];
        }
        return nil;
    }
    _isOpen = YES;

    NSMutableData *voltageBuffer = [NSMutableData dataWithLength:(NSUInteger)_reader.layout.points_per_scan * sizeof(float)];
    if (!hdcv_reader_copy_voltage(&_reader, voltageBuffer.mutableBytes, _reader.layout.points_per_scan)) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:HDCVViewerErrorDomain
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to copy active voltage waveform."}];
        }
        return nil;
    }
    _voltageData = [voltageBuffer copy];

    {
        uint32_t overviewColumns = (uint32_t)MAX((NSUInteger)256U, MIN(maxOverviewColumns, (NSUInteger)2048U));
        NSMutableData *overviewBuffer = [NSMutableData dataWithLength:(NSUInteger)_reader.layout.points_per_scan * (NSUInteger)overviewColumns * sizeof(float)];
        hdcv_overview_result overviewResult;
        if (!hdcv_analysis_build_overview(
                &_reader,
                overviewColumns,
                overviewBuffer.mutableBytes,
                (size_t)((NSUInteger)_reader.layout.points_per_scan * (NSUInteger)overviewColumns),
                &overviewResult)) {
            if (error != NULL) {
                *error = [NSError errorWithDomain:HDCVViewerErrorDomain
                                             code:3
                                         userInfo:@{NSLocalizedDescriptionKey: @"Failed to build overview heatmap."}];
            }
            return nil;
        }
        _overviewColumnCount = overviewResult.column_count;
        _overviewMinValue = overviewResult.min_value;
        _overviewMaxValue = overviewResult.max_value;
        overviewBuffer.length = (NSUInteger)_reader.layout.points_per_scan * (NSUInteger)_overviewColumnCount * sizeof(float);
        _overviewData = [overviewBuffer copy];
    }

    _summaryText = [self buildSummaryText];
    return self;
}

- (void)dealloc
{
    if (_isOpen) {
        hdcv_reader_close(&_reader);
        _isOpen = NO;
    }
}

- (NSString *)buildSummaryText
{
    NSMutableString *text = [NSMutableString string];
    [text appendFormat:@"File\n%@\n\n", HDCVSafeStringFromBytes(_reader.path, strlen(_reader.path))];
    [text appendString:@"Verified Layout\n"];
    [text appendFormat:@"Metadata: [%llu, %llu)\n",
     (unsigned long long)_reader.layout.metadata_start_offset,
     (unsigned long long)_reader.layout.metadata_end_offset];
    [text appendFormat:@"Waveform templates: %u x %u points\n", _reader.layout.waveform_count, _reader.layout.waveform_full_points];
    [text appendFormat:@"Active scan points: %u\n", _reader.layout.points_per_scan];
    [text appendFormat:@"Current matrix offset: %llu\n", (unsigned long long)_reader.layout.current_matrix_offset];
    [text appendFormat:@"Current matrix shape: %u x %u\n\n", _reader.layout.scan_count, _reader.layout.points_per_scan];

    [text appendString:@"Timing\n"];
    [text appendFormat:@"Sample rate: %.3f Hz\n", _reader.layout.sample_rate_hz];
    [text appendFormat:@"CVF: %.3f Hz\n", _reader.layout.cvf_hz];
    [text appendFormat:@"Scan duration: %.4f ms\n", _reader.layout.scan_duration_s * 1000.0];
    [text appendFormat:@"Sequence span: %.3f s\n", hdcv_reader_scan_time_sequence_s(&_reader, _reader.layout.scan_count - 1U)];
    [text appendFormat:@"Experiment span: %.3f s\n\n", hdcv_reader_scan_time_experiment_s(&_reader, _reader.layout.scan_count - 1U)];

    [text appendString:@"Experiment Structure\n"];
    [text appendFormat:@"Runs: %u\n", _reader.layout.run_count];
    [text appendFormat:@"Scans per run: %u\n", _reader.layout.scans_per_run];
    [text appendFormat:@"Run duration: %.3f s\n", _reader.layout.run_duration_s];
    [text appendFormat:@"Delay between runs: %.3f s\n\n", _reader.layout.delay_between_runs_s];

    if (_reader.layout.has_voltage_bounds) {
        [text appendString:@"Waveform Bounds\n"];
        [text appendFormat:@"V1: %.3f V\n", _reader.layout.v1_v];
        [text appendFormat:@"V2: %.3f V\n\n", _reader.layout.v2_v];
    }

    [text appendString:@"Metadata Block\n"];
    [text appendString:HDCVSafeStringFromBytes(_reader.metadata.raw_text, _reader.metadata.raw_length)];
    return text;
}

- (uint32_t)scanCount { return _reader.layout.scan_count; }
- (uint32_t)pointsPerScan { return _reader.layout.points_per_scan; }
- (uint32_t)overviewColumnCount { return _overviewColumnCount; }
- (float)overviewMinValue { return _overviewMinValue; }
- (float)overviewMaxValue { return _overviewMaxValue; }
- (double)sampleRateHz { return _reader.layout.sample_rate_hz; }
- (double)cvfHz { return _reader.layout.cvf_hz; }
- (double)scanIntervalSeconds { return _reader.layout.scan_interval_s; }
- (double)scanDurationSeconds { return _reader.layout.scan_duration_s; }
- (uint32_t)runCount { return _reader.layout.run_count; }
- (uint32_t)scansPerRun { return _reader.layout.scans_per_run; }
- (BOOL)hasExperimentTiming { return _reader.layout.has_experiment_timing != 0; }
- (double)runDurationSeconds { return _reader.layout.run_duration_s; }
- (double)delayBetweenRunsSeconds { return _reader.layout.delay_between_runs_s; }
- (NSData *)voltageData { return _voltageData; }
- (NSData *)overviewData { return _overviewData; }
- (NSString *)summaryAndMetadataText { return _summaryText; }

- (float)voltageAtPoint:(NSUInteger)pointIndex
{
    const float *voltage = _voltageData.bytes;
    return voltage[MIN(pointIndex, (NSUInteger)_reader.layout.points_per_scan - 1U)];
}

- (double)withinScanTimeSecondsAtPoint:(NSUInteger)pointIndex
{
    return hdcv_reader_within_scan_time_s(&_reader, (uint32_t)pointIndex);
}

- (double)sequenceTimeSecondsAtScan:(NSUInteger)scanIndex
{
    return hdcv_reader_scan_time_sequence_s(&_reader, (uint32_t)scanIndex);
}

- (double)experimentTimeSecondsAtScan:(NSUInteger)scanIndex
{
    return hdcv_reader_scan_time_experiment_s(&_reader, (uint32_t)scanIndex);
}

- (BOOL)copyScanAtIndex:(uint32_t)scanIndex intoMutableData:(NSMutableData *)buffer min:(float *)outMin max:(float *)outMax
{
    buffer.length = (NSUInteger)_reader.layout.points_per_scan * sizeof(float);
    if (!hdcv_reader_copy_scan(&_reader, scanIndex, buffer.mutableBytes, _reader.layout.points_per_scan)) {
        return NO;
    }
    hdcv_analysis_compute_min_max(buffer.bytes, _reader.layout.points_per_scan, outMin, outMax);
    return YES;
}

- (BOOL)copyPointTraceAtIndex:(uint32_t)pointIndex intoMutableData:(NSMutableData *)buffer min:(float *)outMin max:(float *)outMax
{
    buffer.length = (NSUInteger)_reader.layout.scan_count * sizeof(float);
    return hdcv_analysis_copy_point_trace(
        &_reader,
        pointIndex,
        buffer.mutableBytes,
        _reader.layout.scan_count,
        outMin,
        outMax
    );
}

@end

@implementation HDCVViewerController {
    NSWindow *_window;
    HDCVDropHostView *_contentHostView;
    HDCVHeatmapView *_heatmapView;
    HDCVLinePlotView *_timePlotView;
    HDCVLinePlotView *_cvPlotView;
    NSTextField *_heroTitleLabel;
    NSTextField *_heroStatusLabel;
    NSTextField *_fileLabel;
    NSTextField *_modeSummaryLabel;
    NSTextField *_scanControlLabel;
    NSTextField *_pointControlLabel;
    NSTextField *_backgroundControlLabel;
    NSTextField *_selectionHeadlineLabel;
    NSTextField *_selectionDetail1Label;
    NSTextField *_selectionDetail2Label;
    NSTextField *_selectionDetail3Label;
    NSTextField *_selectionDetail4Label;
    NSTextView *_infoTextView;
    NSScrollView *_infoScrollView;
    NSSlider *_scanSlider;
    NSSlider *_pointSlider;
    NSSlider *_backgroundSlider;
    NSSegmentedControl *_timeAxisControl;
    NSButton *_backgroundSubtractCheckbox;
    NSButton *_useSelectedAsBackgroundButton;
    NSProgressIndicator *_progressIndicator;
    HDCVLoadedFile *_loadedFile;
    NSMutableData *_selectedRawScanData;
    NSMutableData *_backgroundScanData;
    NSMutableData *_displayScanData;
    NSMutableData *_rawPointTraceData;
    NSMutableData *_displayPointTraceData;
    float _displayScanMin;
    float _displayScanMax;
    float _displayTraceMin;
    float _displayTraceMax;
    NSUInteger _selectedScanIndex;
    NSUInteger _selectedPointIndex;
    NSUInteger _backgroundScanIndex;
    BOOL _backgroundSubtractEnabled;
    dispatch_queue_t _workerQueue;
    NSUInteger _traceRequestToken;
    NSString *_pendingOpenPath;
}

- (instancetype)init
{
    self = [super init];
    if (self != nil) {
        _workerQueue = dispatch_queue_create("com.openai.hdcvviewer.worker", DISPATCH_QUEUE_SERIAL);
        _selectedScanIndex = 0U;
        _selectedPointIndex = 0U;
        _backgroundScanIndex = 0U;
        _backgroundSubtractEnabled = NO;
    }
    return self;
}

- (void)setInitialPathFromArguments:(NSArray<NSString *> *)arguments
{
    if (arguments.count > 1U) {
        _pendingOpenPath = arguments[1];
    }
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    (void)notification;
    [self buildWindow];
    [_window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];

    if (_pendingOpenPath != nil) {
        [self loadFileAtPath:_pendingOpenPath];
    } else {
        _heroStatusLabel.stringValue = @"Open or drag an HDCV FSCV file into the window to begin.";
    }
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
    (void)sender;
    return YES;
}

- (void)buildWindow
{
    _window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 1580.0, 980.0)
                                          styleMask:(NSWindowStyleMaskTitled |
                                                     NSWindowStyleMaskClosable |
                                                     NSWindowStyleMaskResizable |
                                                     NSWindowStyleMaskMiniaturizable)
                                            backing:NSBackingStoreBuffered
                                              defer:NO];
    _window.title = @"HDCV FSCV Workspace";
    _window.minSize = NSMakeSize(1320.0, 860.0);
    _window.backgroundColor = HDCVCanvasColor();

    _contentHostView = [[HDCVDropHostView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 1580.0, 980.0)];
    _contentHostView.delegate = self;
    _window.contentView = _contentHostView;

    NSStackView *rootStack = [[NSStackView alloc] init];
    rootStack.translatesAutoresizingMaskIntoConstraints = NO;
    rootStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    rootStack.spacing = 16.0;
    [_contentHostView addSubview:rootStack];

    [NSLayoutConstraint activateConstraints:@[
        [rootStack.leadingAnchor constraintEqualToAnchor:_contentHostView.leadingAnchor constant:18.0],
        [rootStack.trailingAnchor constraintEqualToAnchor:_contentHostView.trailingAnchor constant:-18.0],
        [rootStack.topAnchor constraintEqualToAnchor:_contentHostView.topAnchor constant:18.0],
        [rootStack.bottomAnchor constraintEqualToAnchor:_contentHostView.bottomAnchor constant:-18.0],
    ]];

    NSView *heroPanel = HDCVPanelContainer();
    heroPanel.layer.backgroundColor = HDCVHeroColor().CGColor;
    heroPanel.layer.borderColor = HDCVHeroBorderColor().CGColor;
    [rootStack addArrangedSubview:heroPanel];
    [heroPanel.heightAnchor constraintEqualToConstant:96.0].active = YES;

    NSButton *openButton = [NSButton buttonWithTitle:@"Import FSCV File" target:self action:@selector(openDocument:)];
    openButton.translatesAutoresizingMaskIntoConstraints = NO;
    openButton.bezelStyle = NSBezelStyleRounded;
    openButton.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightSemibold];
    if (@available(macOS 11.0, *)) {
        openButton.bezelColor = [NSColor colorWithRed:0.96 green:0.98 blue:1.0 alpha:1.0];
        openButton.contentTintColor = HDCVHeroColor();
    }
    [heroPanel addSubview:openButton];

    _heroTitleLabel = HDCVLabel(@"WaveNeuro FSCV Review Workspace", [NSFont systemFontOfSize:18.0 weight:NSFontWeightSemibold], NSColor.whiteColor);
    [heroPanel addSubview:_heroTitleLabel];

    _heroStatusLabel = HDCVLabel(@"Open or drag an HDCV FSCV file into the window to begin.", [NSFont systemFontOfSize:11.5 weight:NSFontWeightRegular], [[NSColor whiteColor] colorWithAlphaComponent:0.82]);
    _heroStatusLabel.lineBreakMode = NSLineBreakByWordWrapping;
    [heroPanel addSubview:_heroStatusLabel];

    _fileLabel = HDCVLabel(@"No file loaded", [NSFont systemFontOfSize:12.5 weight:NSFontWeightSemibold], [[NSColor whiteColor] colorWithAlphaComponent:0.96]);
    [heroPanel addSubview:_fileLabel];

    _progressIndicator = [[NSProgressIndicator alloc] init];
    _progressIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    _progressIndicator.style = NSProgressIndicatorStyleSpinning;
    _progressIndicator.controlSize = NSControlSizeRegular;
    _progressIndicator.displayedWhenStopped = NO;
    [heroPanel addSubview:_progressIndicator];

    _timeAxisControl = [[NSSegmentedControl alloc] initWithFrame:NSZeroRect];
    _timeAxisControl.translatesAutoresizingMaskIntoConstraints = NO;
    _timeAxisControl.segmentCount = 2;
    [_timeAxisControl setLabel:@"Sequence Time" forSegment:0];
    [_timeAxisControl setLabel:@"Experiment Time" forSegment:1];
    _timeAxisControl.trackingMode = NSSegmentSwitchTrackingSelectOne;
    _timeAxisControl.selectedSegment = 0;
    _timeAxisControl.target = self;
    _timeAxisControl.action = @selector(timeAxisModeChanged:);
    [heroPanel addSubview:_timeAxisControl];

    [NSLayoutConstraint activateConstraints:@[
        [_heroTitleLabel.leadingAnchor constraintEqualToAnchor:heroPanel.leadingAnchor constant:18.0],
        [_heroTitleLabel.topAnchor constraintEqualToAnchor:heroPanel.topAnchor constant:14.0],
        [_heroStatusLabel.leadingAnchor constraintEqualToAnchor:_heroTitleLabel.leadingAnchor],
        [_heroStatusLabel.topAnchor constraintEqualToAnchor:_heroTitleLabel.bottomAnchor constant:6.0],
        [_heroStatusLabel.trailingAnchor constraintLessThanOrEqualToAnchor:openButton.leadingAnchor constant:-16.0],
        [_fileLabel.leadingAnchor constraintEqualToAnchor:_heroTitleLabel.leadingAnchor],
        [_fileLabel.topAnchor constraintEqualToAnchor:_heroStatusLabel.bottomAnchor constant:8.0],
        [openButton.trailingAnchor constraintEqualToAnchor:heroPanel.trailingAnchor constant:-18.0],
        [openButton.topAnchor constraintEqualToAnchor:heroPanel.topAnchor constant:18.0],
        [_timeAxisControl.trailingAnchor constraintEqualToAnchor:heroPanel.trailingAnchor constant:-18.0],
        [_timeAxisControl.bottomAnchor constraintEqualToAnchor:heroPanel.bottomAnchor constant:-14.0],
        [_progressIndicator.trailingAnchor constraintEqualToAnchor:_timeAxisControl.leadingAnchor constant:-14.0],
        [_progressIndicator.centerYAnchor constraintEqualToAnchor:_timeAxisControl.centerYAnchor],
    ]];

    NSStackView *contentRow = [[NSStackView alloc] init];
    contentRow.translatesAutoresizingMaskIntoConstraints = NO;
    contentRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    contentRow.spacing = 16.0;
    [rootStack addArrangedSubview:contentRow];

    NSStackView *mainColumn = [[NSStackView alloc] init];
    mainColumn.translatesAutoresizingMaskIntoConstraints = NO;
    mainColumn.orientation = NSUserInterfaceLayoutOrientationVertical;
    mainColumn.spacing = 16.0;
    [contentRow addArrangedSubview:mainColumn];

    NSStackView *sidebarColumn = [[NSStackView alloc] init];
    sidebarColumn.translatesAutoresizingMaskIntoConstraints = NO;
    sidebarColumn.orientation = NSUserInterfaceLayoutOrientationVertical;
    sidebarColumn.spacing = 16.0;
    [contentRow addArrangedSubview:sidebarColumn];
    [sidebarColumn.widthAnchor constraintEqualToConstant:392.0].active = YES;

    NSView *heatmapPanel = HDCVPanelContainer();
    [mainColumn addArrangedSubview:heatmapPanel];
    [heatmapPanel.heightAnchor constraintGreaterThanOrEqualToConstant:420.0].active = YES;

    _heatmapView = [[HDCVHeatmapView alloc] initWithFrame:NSZeroRect];
    _heatmapView.translatesAutoresizingMaskIntoConstraints = NO;
    _heatmapView.delegate = self;
    [heatmapPanel addSubview:_heatmapView];
    [NSLayoutConstraint activateConstraints:@[
        [_heatmapView.leadingAnchor constraintEqualToAnchor:heatmapPanel.leadingAnchor constant:8.0],
        [_heatmapView.trailingAnchor constraintEqualToAnchor:heatmapPanel.trailingAnchor constant:-8.0],
        [_heatmapView.topAnchor constraintEqualToAnchor:heatmapPanel.topAnchor constant:8.0],
        [_heatmapView.bottomAnchor constraintEqualToAnchor:heatmapPanel.bottomAnchor constant:-8.0],
    ]];

    NSStackView *plotRow = [[NSStackView alloc] init];
    plotRow.translatesAutoresizingMaskIntoConstraints = NO;
    plotRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    plotRow.spacing = 16.0;
    [mainColumn addArrangedSubview:plotRow];

    NSView *timePanel = HDCVPanelContainer();
    NSView *cvPanel = HDCVPanelContainer();
    [plotRow addArrangedSubview:timePanel];
    [plotRow addArrangedSubview:cvPanel];
    [timePanel.widthAnchor constraintEqualToAnchor:cvPanel.widthAnchor].active = YES;
    [timePanel.heightAnchor constraintGreaterThanOrEqualToConstant:286.0].active = YES;
    [cvPanel.heightAnchor constraintGreaterThanOrEqualToConstant:286.0].active = YES;

    _timePlotView = [[HDCVLinePlotView alloc] initWithFrame:NSZeroRect];
    _timePlotView.translatesAutoresizingMaskIntoConstraints = NO;
    _timePlotView.dataSource = self;
    _timePlotView.delegate = self;
    _timePlotView.interactionMode = HDCVLinePlotInteractionModeSelectX;
    _timePlotView.titleText = @"I-t Plot";
    _timePlotView.xLabelText = @"Sequence Time (s)";
    _timePlotView.yLabelText = @"Current";
    _timePlotView.xTickFormat = @"%.1f";
    _timePlotView.yTickFormat = @"%.0f";
    _timePlotView.strokeColor = HDCVAccentBlue();
    [timePanel addSubview:_timePlotView];

    _cvPlotView = [[HDCVLinePlotView alloc] initWithFrame:NSZeroRect];
    _cvPlotView.translatesAutoresizingMaskIntoConstraints = NO;
    _cvPlotView.dataSource = self;
    _cvPlotView.delegate = self;
    _cvPlotView.interactionMode = HDCVLinePlotInteractionModeSelectX;
    _cvPlotView.titleText = @"CV Plot";
    _cvPlotView.xLabelText = @"Voltage (V)";
    _cvPlotView.yLabelText = @"Current";
    _cvPlotView.xTickFormat = @"%.2f";
    _cvPlotView.yTickFormat = @"%.0f";
    _cvPlotView.strokeColor = HDCVAccentCopper();
    [cvPanel addSubview:_cvPlotView];

    [NSLayoutConstraint activateConstraints:@[
        [_timePlotView.leadingAnchor constraintEqualToAnchor:timePanel.leadingAnchor constant:8.0],
        [_timePlotView.trailingAnchor constraintEqualToAnchor:timePanel.trailingAnchor constant:-8.0],
        [_timePlotView.topAnchor constraintEqualToAnchor:timePanel.topAnchor constant:8.0],
        [_timePlotView.bottomAnchor constraintEqualToAnchor:timePanel.bottomAnchor constant:-8.0],
        [_cvPlotView.leadingAnchor constraintEqualToAnchor:cvPanel.leadingAnchor constant:8.0],
        [_cvPlotView.trailingAnchor constraintEqualToAnchor:cvPanel.trailingAnchor constant:-8.0],
        [_cvPlotView.topAnchor constraintEqualToAnchor:cvPanel.topAnchor constant:8.0],
        [_cvPlotView.bottomAnchor constraintEqualToAnchor:cvPanel.bottomAnchor constant:-8.0],
    ]];

    NSView *controlsPanel = HDCVPanelContainer();
    [sidebarColumn addArrangedSubview:controlsPanel];
    [controlsPanel.heightAnchor constraintEqualToConstant:258.0].active = YES;

    NSTextField *controlsTitle = HDCVLabel(@"Analysis Controls", [NSFont systemFontOfSize:14.0 weight:NSFontWeightSemibold], NSColor.blackColor);
    [controlsPanel addSubview:controlsTitle];

    _modeSummaryLabel = HDCVLabel(@"Display mode: raw current.", [NSFont systemFontOfSize:11.0 weight:NSFontWeightMedium], HDCVMutedText());
    _modeSummaryLabel.lineBreakMode = NSLineBreakByWordWrapping;
    [controlsPanel addSubview:_modeSummaryLabel];

    _scanControlLabel = HDCVLabel(@"Selected scan", [NSFont systemFontOfSize:11.5 weight:NSFontWeightSemibold], NSColor.blackColor);
    _pointControlLabel = HDCVLabel(@"Selected voltage point", [NSFont systemFontOfSize:11.5 weight:NSFontWeightSemibold], NSColor.blackColor);
    _backgroundControlLabel = HDCVLabel(@"Background scan", [NSFont systemFontOfSize:11.5 weight:NSFontWeightSemibold], NSColor.blackColor);
    [controlsPanel addSubview:_scanControlLabel];
    [controlsPanel addSubview:_pointControlLabel];
    [controlsPanel addSubview:_backgroundControlLabel];

    _scanSlider = [[NSSlider alloc] init];
    _pointSlider = [[NSSlider alloc] init];
    _backgroundSlider = [[NSSlider alloc] init];
    _scanSlider.translatesAutoresizingMaskIntoConstraints = NO;
    _pointSlider.translatesAutoresizingMaskIntoConstraints = NO;
    _backgroundSlider.translatesAutoresizingMaskIntoConstraints = NO;
    _scanSlider.target = self;
    _scanSlider.action = @selector(scanSliderChanged:);
    _scanSlider.continuous = YES;
    _pointSlider.target = self;
    _pointSlider.action = @selector(pointSliderChanged:);
    _pointSlider.continuous = NO;
    _backgroundSlider.target = self;
    _backgroundSlider.action = @selector(backgroundSliderChanged:);
    _backgroundSlider.continuous = NO;
    _scanSlider.enabled = NO;
    _pointSlider.enabled = NO;
    _backgroundSlider.enabled = NO;
    [controlsPanel addSubview:_scanSlider];
    [controlsPanel addSubview:_pointSlider];
    [controlsPanel addSubview:_backgroundSlider];

    _backgroundSubtractCheckbox = [[NSButton alloc] init];
    _backgroundSubtractCheckbox.translatesAutoresizingMaskIntoConstraints = NO;
    _backgroundSubtractCheckbox.buttonType = NSButtonTypeSwitch;
    _backgroundSubtractCheckbox.title = @"Enable background subtraction";
    _backgroundSubtractCheckbox.font = [NSFont systemFontOfSize:12.0 weight:NSFontWeightSemibold];
    _backgroundSubtractCheckbox.target = self;
    _backgroundSubtractCheckbox.action = @selector(backgroundSubtractToggled:);
    _backgroundSubtractCheckbox.enabled = NO;
    [controlsPanel addSubview:_backgroundSubtractCheckbox];

    _useSelectedAsBackgroundButton = [NSButton buttonWithTitle:@"Use Selected Scan as Background" target:self action:@selector(useSelectedScanAsBackground:)];
    _useSelectedAsBackgroundButton.translatesAutoresizingMaskIntoConstraints = NO;
    _useSelectedAsBackgroundButton.bezelStyle = NSBezelStyleRounded;
    _useSelectedAsBackgroundButton.font = [NSFont systemFontOfSize:12.0 weight:NSFontWeightSemibold];
    _useSelectedAsBackgroundButton.enabled = NO;
    [controlsPanel addSubview:_useSelectedAsBackgroundButton];

    [NSLayoutConstraint activateConstraints:@[
        [controlsTitle.leadingAnchor constraintEqualToAnchor:controlsPanel.leadingAnchor constant:16.0],
        [controlsTitle.topAnchor constraintEqualToAnchor:controlsPanel.topAnchor constant:14.0],
        [_modeSummaryLabel.leadingAnchor constraintEqualToAnchor:controlsTitle.leadingAnchor],
        [_modeSummaryLabel.trailingAnchor constraintEqualToAnchor:controlsPanel.trailingAnchor constant:-16.0],
        [_modeSummaryLabel.topAnchor constraintEqualToAnchor:controlsTitle.bottomAnchor constant:6.0],

        [_scanControlLabel.leadingAnchor constraintEqualToAnchor:controlsTitle.leadingAnchor],
        [_scanControlLabel.topAnchor constraintEqualToAnchor:_modeSummaryLabel.bottomAnchor constant:14.0],
        [_scanSlider.leadingAnchor constraintEqualToAnchor:controlsTitle.leadingAnchor],
        [_scanSlider.trailingAnchor constraintEqualToAnchor:controlsPanel.trailingAnchor constant:-16.0],
        [_scanSlider.topAnchor constraintEqualToAnchor:_scanControlLabel.bottomAnchor constant:6.0],

        [_pointControlLabel.leadingAnchor constraintEqualToAnchor:controlsTitle.leadingAnchor],
        [_pointControlLabel.topAnchor constraintEqualToAnchor:_scanSlider.bottomAnchor constant:10.0],
        [_pointSlider.leadingAnchor constraintEqualToAnchor:controlsTitle.leadingAnchor],
        [_pointSlider.trailingAnchor constraintEqualToAnchor:controlsPanel.trailingAnchor constant:-16.0],
        [_pointSlider.topAnchor constraintEqualToAnchor:_pointControlLabel.bottomAnchor constant:6.0],

        [_backgroundControlLabel.leadingAnchor constraintEqualToAnchor:controlsTitle.leadingAnchor],
        [_backgroundControlLabel.topAnchor constraintEqualToAnchor:_pointSlider.bottomAnchor constant:10.0],
        [_backgroundSlider.leadingAnchor constraintEqualToAnchor:controlsTitle.leadingAnchor],
        [_backgroundSlider.trailingAnchor constraintEqualToAnchor:controlsPanel.trailingAnchor constant:-16.0],
        [_backgroundSlider.topAnchor constraintEqualToAnchor:_backgroundControlLabel.bottomAnchor constant:6.0],

        [_backgroundSubtractCheckbox.leadingAnchor constraintEqualToAnchor:controlsTitle.leadingAnchor],
        [_backgroundSubtractCheckbox.topAnchor constraintEqualToAnchor:_backgroundSlider.bottomAnchor constant:12.0],
        [_useSelectedAsBackgroundButton.leadingAnchor constraintEqualToAnchor:controlsTitle.leadingAnchor],
        [_useSelectedAsBackgroundButton.topAnchor constraintEqualToAnchor:_backgroundSubtractCheckbox.bottomAnchor constant:8.0],
    ]];

    NSView *selectionPanel = HDCVPanelContainer();
    [sidebarColumn addArrangedSubview:selectionPanel];
    [selectionPanel.heightAnchor constraintEqualToConstant:188.0].active = YES;

    NSTextField *selectionTitle = HDCVLabel(@"Selection Readout", [NSFont systemFontOfSize:14.0 weight:NSFontWeightSemibold], NSColor.blackColor);
    [selectionPanel addSubview:selectionTitle];

    _selectionHeadlineLabel = HDCVLabel(@"No active selection.", [NSFont systemFontOfSize:12.0 weight:NSFontWeightSemibold], NSColor.blackColor);
    _selectionDetail1Label = HDCVLabel(@"", [NSFont systemFontOfSize:11.0 weight:NSFontWeightRegular], HDCVMutedText());
    _selectionDetail2Label = HDCVLabel(@"", [NSFont systemFontOfSize:11.0 weight:NSFontWeightRegular], HDCVMutedText());
    _selectionDetail3Label = HDCVLabel(@"", [NSFont systemFontOfSize:11.0 weight:NSFontWeightRegular], HDCVMutedText());
    _selectionDetail4Label = HDCVLabel(@"", [NSFont systemFontOfSize:11.0 weight:NSFontWeightRegular], HDCVMutedText());
    _selectionDetail1Label.lineBreakMode = NSLineBreakByWordWrapping;
    _selectionDetail2Label.lineBreakMode = NSLineBreakByWordWrapping;
    _selectionDetail3Label.lineBreakMode = NSLineBreakByWordWrapping;
    _selectionDetail4Label.lineBreakMode = NSLineBreakByWordWrapping;
    [selectionPanel addSubview:_selectionHeadlineLabel];
    [selectionPanel addSubview:_selectionDetail1Label];
    [selectionPanel addSubview:_selectionDetail2Label];
    [selectionPanel addSubview:_selectionDetail3Label];
    [selectionPanel addSubview:_selectionDetail4Label];

    [NSLayoutConstraint activateConstraints:@[
        [selectionTitle.leadingAnchor constraintEqualToAnchor:selectionPanel.leadingAnchor constant:16.0],
        [selectionTitle.topAnchor constraintEqualToAnchor:selectionPanel.topAnchor constant:14.0],
        [_selectionHeadlineLabel.leadingAnchor constraintEqualToAnchor:selectionTitle.leadingAnchor],
        [_selectionHeadlineLabel.trailingAnchor constraintEqualToAnchor:selectionPanel.trailingAnchor constant:-16.0],
        [_selectionHeadlineLabel.topAnchor constraintEqualToAnchor:selectionTitle.bottomAnchor constant:8.0],
        [_selectionDetail1Label.leadingAnchor constraintEqualToAnchor:selectionTitle.leadingAnchor],
        [_selectionDetail1Label.trailingAnchor constraintEqualToAnchor:selectionPanel.trailingAnchor constant:-16.0],
        [_selectionDetail1Label.topAnchor constraintEqualToAnchor:_selectionHeadlineLabel.bottomAnchor constant:10.0],
        [_selectionDetail2Label.leadingAnchor constraintEqualToAnchor:selectionTitle.leadingAnchor],
        [_selectionDetail2Label.trailingAnchor constraintEqualToAnchor:selectionPanel.trailingAnchor constant:-16.0],
        [_selectionDetail2Label.topAnchor constraintEqualToAnchor:_selectionDetail1Label.bottomAnchor constant:6.0],
        [_selectionDetail3Label.leadingAnchor constraintEqualToAnchor:selectionTitle.leadingAnchor],
        [_selectionDetail3Label.trailingAnchor constraintEqualToAnchor:selectionPanel.trailingAnchor constant:-16.0],
        [_selectionDetail3Label.topAnchor constraintEqualToAnchor:_selectionDetail2Label.bottomAnchor constant:6.0],
        [_selectionDetail4Label.leadingAnchor constraintEqualToAnchor:selectionTitle.leadingAnchor],
        [_selectionDetail4Label.trailingAnchor constraintEqualToAnchor:selectionPanel.trailingAnchor constant:-16.0],
        [_selectionDetail4Label.topAnchor constraintEqualToAnchor:_selectionDetail3Label.bottomAnchor constant:6.0],
    ]];

    NSView *infoPanel = HDCVPanelContainer();
    [sidebarColumn addArrangedSubview:infoPanel];

    NSTextField *infoTitle = HDCVLabel(@"Format Summary and Metadata", [NSFont systemFontOfSize:14.0 weight:NSFontWeightSemibold], NSColor.blackColor);
    [infoPanel addSubview:infoTitle];

    _infoTextView = [[NSTextView alloc] initWithFrame:NSZeroRect];
    _infoTextView.editable = NO;
    _infoTextView.selectable = YES;
    _infoTextView.font = [NSFont monospacedSystemFontOfSize:11.0 weight:NSFontWeightRegular];
    _infoTextView.textColor = [NSColor colorWithRed:0.19 green:0.22 blue:0.28 alpha:1.0];
    _infoTextView.backgroundColor = NSColor.clearColor;
    _infoTextView.string = @"Open or drag an HDCV file to inspect its validated structure and metadata.";

    _infoScrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    _infoScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _infoScrollView.borderType = NSNoBorder;
    _infoScrollView.hasVerticalScroller = YES;
    _infoScrollView.documentView = _infoTextView;
    _infoScrollView.drawsBackground = NO;
    [infoPanel addSubview:_infoScrollView];

    [NSLayoutConstraint activateConstraints:@[
        [infoTitle.leadingAnchor constraintEqualToAnchor:infoPanel.leadingAnchor constant:16.0],
        [infoTitle.topAnchor constraintEqualToAnchor:infoPanel.topAnchor constant:14.0],
        [_infoScrollView.leadingAnchor constraintEqualToAnchor:infoPanel.leadingAnchor constant:10.0],
        [_infoScrollView.trailingAnchor constraintEqualToAnchor:infoPanel.trailingAnchor constant:-10.0],
        [_infoScrollView.topAnchor constraintEqualToAnchor:infoTitle.bottomAnchor constant:8.0],
        [_infoScrollView.bottomAnchor constraintEqualToAnchor:infoPanel.bottomAnchor constant:-10.0],
    ]];
}

- (void)openDocument:(id)sender
{
    (void)sender;
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    if (@available(macOS 11.0, *)) {
        UTType *hdcvType = [UTType typeWithFilenameExtension:@"hdcv"];
        panel.allowedContentTypes = (hdcvType != nil) ? @[hdcvType] : @[UTTypeData];
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        panel.allowedFileTypes = @[@"hdcv"];
#pragma clang diagnostic pop
    }
    panel.allowsMultipleSelection = NO;
    panel.canChooseDirectories = NO;
    panel.canChooseFiles = YES;
    [panel beginWithCompletionHandler:^(NSModalResponse response) {
        if (response == NSModalResponseOK) {
            NSURL *url = panel.URL;
            if (url != nil) {
                [self loadFileAtPath:url.path];
            }
        }
    }];
}

- (void)dropHostView:(HDCVDropHostView *)view didReceiveFilePath:(NSString *)filePath
{
    (void)view;
    [self loadFileAtPath:filePath];
}

- (void)loadFileAtPath:(NSString *)path
{
    _pendingOpenPath = path;
    _scanSlider.enabled = NO;
    _pointSlider.enabled = NO;
    _backgroundSlider.enabled = NO;
    _backgroundSubtractCheckbox.enabled = NO;
    _useSelectedAsBackgroundButton.enabled = NO;
    _fileLabel.stringValue = path.lastPathComponent;
    _heroStatusLabel.stringValue = @"Loading file, validating offsets, and preparing interactive FSCV views…";
    [_progressIndicator startAnimation:nil];

    dispatch_async(_workerQueue, ^{
        NSError *error = nil;
        HDCVLoadedFile *loaded = [[HDCVLoadedFile alloc] initWithPath:path maxOverviewColumns:1440U error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self->_progressIndicator stopAnimation:nil];
            if (loaded == nil) {
                NSString *message = (error.localizedDescription != nil) ? error.localizedDescription : @"Failed to load file.";
                self->_heroStatusLabel.stringValue = message;
                NSAlert *alert = [[NSAlert alloc] init];
                alert.alertStyle = NSAlertStyleWarning;
                alert.messageText = @"Failed to open HDCV file";
                alert.informativeText = message;
                [alert beginSheetModalForWindow:self->_window completionHandler:nil];
                return;
            }
            [self installLoadedFile:loaded];
        });
    });
}

- (void)installLoadedFile:(HDCVLoadedFile *)loaded
{
    _loadedFile = loaded;
    _infoTextView.string = loaded.summaryAndMetadataText;

    _selectedRawScanData = [NSMutableData dataWithLength:(NSUInteger)loaded.pointsPerScan * sizeof(float)];
    _backgroundScanData = [NSMutableData dataWithLength:(NSUInteger)loaded.pointsPerScan * sizeof(float)];
    _displayScanData = [NSMutableData dataWithLength:(NSUInteger)loaded.pointsPerScan * sizeof(float)];
    _rawPointTraceData = [NSMutableData dataWithLength:(NSUInteger)loaded.scanCount * sizeof(float)];
    _displayPointTraceData = [NSMutableData dataWithLength:(NSUInteger)loaded.scanCount * sizeof(float)];

    _selectedScanIndex = loaded.scanCount / 2U;
    _selectedPointIndex = loaded.pointsPerScan / 2U;
    _backgroundScanIndex = 0U;
    _backgroundSubtractEnabled = NO;

    _scanSlider.enabled = YES;
    _pointSlider.enabled = YES;
    _backgroundSlider.enabled = YES;
    _backgroundSubtractCheckbox.enabled = YES;
    _useSelectedAsBackgroundButton.enabled = YES;
    _backgroundSubtractCheckbox.state = NSControlStateValueOff;

    _scanSlider.minValue = 0.0;
    _scanSlider.maxValue = (double)(loaded.scanCount - 1U);
    _scanSlider.doubleValue = (double)_selectedScanIndex;

    _pointSlider.minValue = 0.0;
    _pointSlider.maxValue = (double)(loaded.pointsPerScan - 1U);
    _pointSlider.doubleValue = (double)_selectedPointIndex;

    _backgroundSlider.minValue = 0.0;
    _backgroundSlider.maxValue = (double)(loaded.scanCount - 1U);
    _backgroundSlider.doubleValue = (double)_backgroundScanIndex;

    _heatmapView.scanCount = loaded.scanCount;
    _heatmapView.pointCount = loaded.pointsPerScan;
    _heatmapView.voltageData = loaded.voltageData;
    _heatmapView.selectedScanIndex = _selectedScanIndex;
    _heatmapView.selectedPointIndex = _selectedPointIndex;
    _heatmapView.backgroundScanIndex = _backgroundScanIndex;

    _timePlotView.xTickFormat = @"%.1f";
    _timePlotView.yTickFormat = @"%.0f";
    _cvPlotView.xTickFormat = @"%.2f";
    _cvPlotView.yTickFormat = @"%.0f";

    [self copyBackgroundScan];
    [self copySelectedScan];
    [self applyDisplayModes];
    [self rebuildHeatmapImage];
    [self refreshHeatmapTicks];
    [self refreshPlotTitles];
    [self refreshSelectionReadout];
    [self requestPointTraceRefresh];

    _fileLabel.stringValue = [NSString stringWithFormat:@"%@  |  %u scans × %u points", _pendingOpenPath.lastPathComponent, loaded.scanCount, loaded.pointsPerScan];
    _heroStatusLabel.stringValue = @"Layout verified. Click or drag across the color plot, I-t plot, or CV plot to explore the FSCV recording.";
}

- (BOOL)copyBackgroundScan
{
    if (_loadedFile == nil) {
        return NO;
    }
    _heatmapView.backgroundScanIndex = _backgroundScanIndex;
    return [_loadedFile copyScanAtIndex:(uint32_t)_backgroundScanIndex intoMutableData:_backgroundScanData min:NULL max:NULL];
}

- (BOOL)copySelectedScan
{
    if (_loadedFile == nil) {
        return NO;
    }
    return [_loadedFile copyScanAtIndex:(uint32_t)_selectedScanIndex intoMutableData:_selectedRawScanData min:NULL max:NULL];
}

- (NSString *)displayModeText
{
    return _backgroundSubtractEnabled ? @"background-subtracted current" : @"raw current";
}

- (void)applyDisplayModes
{
    if (_loadedFile == nil) {
        return;
    }

    const float *selectedRaw = _selectedRawScanData.bytes;
    const float *background = _backgroundScanData.bytes;
    float *displayScan = _displayScanData.mutableBytes;
    NSUInteger pointsPerScan = _loadedFile.pointsPerScan;
    NSUInteger scanCount = _loadedFile.scanCount;

    for (NSUInteger i = 0U; i < pointsPerScan; ++i) {
        displayScan[i] = _backgroundSubtractEnabled ? (selectedRaw[i] - background[i]) : selectedRaw[i];
    }
    hdcv_analysis_compute_min_max(_displayScanData.bytes, pointsPerScan, &_displayScanMin, &_displayScanMax);

    if (_rawPointTraceData.length >= scanCount * sizeof(float)) {
        const float *rawTrace = _rawPointTraceData.bytes;
        float *displayTrace = _displayPointTraceData.mutableBytes;
        float backgroundValue = background[_selectedPointIndex];
        for (NSUInteger i = 0U; i < scanCount; ++i) {
            displayTrace[i] = _backgroundSubtractEnabled ? (rawTrace[i] - backgroundValue) : rawTrace[i];
        }
        hdcv_analysis_compute_min_max(_displayPointTraceData.bytes, scanCount, &_displayTraceMin, &_displayTraceMax);
    }

    _modeSummaryLabel.stringValue = [NSString stringWithFormat:
        @"Display mode: %@. Background scan %lu is applied to the color plot, I-t plot, and CV plot.",
        [self displayModeText],
        (unsigned long)_backgroundScanIndex];

    [self refreshPlotTitles];
    [self refreshPlots];
}

- (void)refreshPlotTitles
{
    if (_loadedFile == nil) {
        _heatmapView.titleText = @"Color Plot";
        _heatmapView.subtitleText = @"No file loaded";
        _timePlotView.titleText = @"I-t Plot";
        _timePlotView.subtitleText = @"";
        _cvPlotView.titleText = @"CV Plot";
        _cvPlotView.subtitleText = @"";
        return;
    }

    NSString *modeText = _backgroundSubtractEnabled ? @"Background Subtracted" : @"Raw Current";
    float selectedVoltage = [_loadedFile voltageAtPoint:_selectedPointIndex];
    double selectedTime = [self selectedScanTime];

    _heatmapView.titleText = @"Color Plot";
    _heatmapView.subtitleText = [NSString stringWithFormat:@"%@  •  BG scan %lu", modeText, (unsigned long)_backgroundScanIndex];

    _timePlotView.titleText = @"I-t Plot";
    _timePlotView.subtitleText = [NSString stringWithFormat:@"%@ at %.3f V", modeText, selectedVoltage];
    _timePlotView.xLabelText = (_timeAxisControl.selectedSegment == HDCVTimeAxisModeExperiment) ? @"Experiment Time (s)" : @"Sequence Time (s)";

    _cvPlotView.titleText = @"CV Plot";
    _cvPlotView.subtitleText = [NSString stringWithFormat:@"%@ at %.3f s", modeText, selectedTime];
}

- (void)refreshHeatmapTicks
{
    if (_loadedFile == nil) {
        return;
    }

    NSMutableArray<NSString *> *labels = [NSMutableArray array];
    NSMutableArray<NSNumber *> *fractions = [NSMutableArray array];
    NSUInteger tickCount = 5U;
    NSUInteger scanCount = _loadedFile.scanCount;

    for (NSUInteger i = 0U; i < tickCount; ++i) {
        NSUInteger scanIndex = (tickCount == 1U)
            ? 0U
            : (NSUInteger)llround((double)i * (double)(scanCount - 1U) / (double)(tickCount - 1U));
        double timeValue = [self timeValueForScanIndex:scanIndex];
        [labels addObject:[NSString stringWithFormat:@"%.1f s", timeValue]];
        [fractions addObject:@(scanCount > 1U ? (double)scanIndex / (double)(scanCount - 1U) : 0.0)];
    }

    _heatmapView.xTickLabels = labels;
    _heatmapView.xTickFractions = fractions;
}

- (NSImage *)buildHeatmapImage
{
    NSUInteger width = _loadedFile.overviewColumnCount;
    NSUInteger height = _loadedFile.pointsPerScan;
    const float *overview = _loadedFile.overviewData.bytes;
    const float *background = _backgroundScanData.bytes;
    NSMutableData *pixelData = [NSMutableData dataWithLength:width * height * 4U];
    unsigned char *pixels = pixelData.mutableBytes;
    float minValue = _backgroundSubtractEnabled ? FLT_MAX : _loadedFile.overviewMinValue;
    float maxValue = _backgroundSubtractEnabled ? -FLT_MAX : _loadedFile.overviewMaxValue;
    float scale;

    if (_backgroundSubtractEnabled) {
        for (NSUInteger pointIndex = 0U; pointIndex < height; ++pointIndex) {
            float backgroundValue = background[pointIndex];
            for (NSUInteger x = 0U; x < width; ++x) {
                float adjusted = overview[pointIndex * width + x] - backgroundValue;
                if (adjusted < minValue) {
                    minValue = adjusted;
                }
                if (adjusted > maxValue) {
                    maxValue = adjusted;
                }
            }
        }
    }

    scale = MAX(fabsf(minValue), fabsf(maxValue));
    if (scale < 1.0e-9f) {
        scale = 1.0f;
    }

    for (NSUInteger pointIndex = 0U; pointIndex < height; ++pointIndex) {
        float backgroundValue = background[pointIndex];
        NSUInteger y = height - 1U - pointIndex;
        for (NSUInteger x = 0U; x < width; ++x) {
            float rawValue = overview[pointIndex * width + x];
            float value = _backgroundSubtractEnabled ? (rawValue - backgroundValue) : rawValue;
            float normalized = MAX(-1.0f, MIN(1.0f, value / scale));
            float t = (normalized + 1.0f) * 0.5f;
            NSUInteger offset = (y * width + x) * 4U;
            float r;
            float g;
            float b;

            if (t < 0.25f) {
                float local = t / 0.25f;
                r = 0.04f + local * 0.06f;
                g = 0.12f + local * 0.36f;
                b = 0.28f + local * 0.52f;
            } else if (t < 0.5f) {
                float local = (t - 0.25f) / 0.25f;
                r = 0.10f + local * 0.08f;
                g = 0.48f + local * 0.36f;
                b = 0.80f - local * 0.40f;
            } else if (t < 0.75f) {
                float local = (t - 0.5f) / 0.25f;
                r = 0.18f + local * 0.55f;
                g = 0.84f + local * 0.07f;
                b = 0.40f - local * 0.24f;
            } else {
                float local = (t - 0.75f) / 0.25f;
                r = 0.73f + local * 0.22f;
                g = 0.91f - local * 0.56f;
                b = 0.16f - local * 0.08f;
            }

            pixels[offset + 0U] = (unsigned char)llroundf(r * 255.0f);
            pixels[offset + 1U] = (unsigned char)llroundf(g * 255.0f);
            pixels[offset + 2U] = (unsigned char)llroundf(b * 255.0f);
            pixels[offset + 3U] = 255U;
        }
    }

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(
        pixels,
        width,
        height,
        8U,
        width * 4U,
        colorSpace,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrderDefault
    );
    CGImageRef imageRef = CGBitmapContextCreateImage(context);
    NSImage *image = [[NSImage alloc] initWithCGImage:imageRef size:NSMakeSize((CGFloat)width, (CGFloat)height)];
    CGImageRelease(imageRef);
    CGContextRelease(context);
    CGColorSpaceRelease(colorSpace);
    return image;
}

- (void)rebuildHeatmapImage
{
    if (_loadedFile == nil) {
        return;
    }
    _heatmapView.image = [self buildHeatmapImage];
}

- (double)timeValueForScanIndex:(NSUInteger)scanIndex
{
    if (_loadedFile == nil) {
        return 0.0;
    }
    if (_timeAxisControl.selectedSegment == HDCVTimeAxisModeExperiment) {
        return [_loadedFile experimentTimeSecondsAtScan:scanIndex];
    }
    return [_loadedFile sequenceTimeSecondsAtScan:scanIndex];
}

- (double)selectedScanTime
{
    return [self timeValueForScanIndex:_selectedScanIndex];
}

- (void)refreshPlots
{
    if (_loadedFile == nil) {
        return;
    }

    _heatmapView.selectedScanIndex = _selectedScanIndex;
    _heatmapView.selectedPointIndex = _selectedPointIndex;

    double yMin = (double)_displayScanMin;
    double yMax = (double)_displayScanMax;
    HDCVExpandRange(&yMin, &yMax);
    _cvPlotView.xMin = -0.45;
    _cvPlotView.xMax = 1.15;
    _cvPlotView.yMin = yMin;
    _cvPlotView.yMax = yMax;
    _cvPlotView.selectedXValue = [_loadedFile voltageAtPoint:_selectedPointIndex];
    _cvPlotView.selectedYValue = ((const float *)_displayScanData.bytes)[_selectedPointIndex];
    _cvPlotView.showsSelection = YES;
    _cvPlotView.showsBaseline = _backgroundSubtractEnabled;
    _cvPlotView.baselineYValue = 0.0;
    [_cvPlotView setNeedsDisplay:YES];

    if (_displayPointTraceData.length >= _loadedFile.scanCount * sizeof(float)) {
        double traceMin = (double)_displayTraceMin;
        double traceMax = (double)_displayTraceMax;
        HDCVExpandRange(&traceMin, &traceMax);
        _timePlotView.xMin = [self timeValueForScanIndex:0U];
        _timePlotView.xMax = [self timeValueForScanIndex:_loadedFile.scanCount - 1U];
        _timePlotView.yMin = traceMin;
        _timePlotView.yMax = traceMax;
        _timePlotView.selectedXValue = [self selectedScanTime];
        _timePlotView.selectedYValue = ((const float *)_displayPointTraceData.bytes)[_selectedScanIndex];
        _timePlotView.showsSelection = YES;
        _timePlotView.showsBaseline = _backgroundSubtractEnabled;
        _timePlotView.baselineYValue = 0.0;
        [_timePlotView setNeedsDisplay:YES];
    }
}

- (void)refreshSelectionReadout
{
    if (_loadedFile == nil) {
        _selectionHeadlineLabel.stringValue = @"No active selection.";
        _selectionDetail1Label.stringValue = @"";
        _selectionDetail2Label.stringValue = @"";
        _selectionDetail3Label.stringValue = @"";
        _selectionDetail4Label.stringValue = @"";
        return;
    }

    const float *selectedRaw = _selectedRawScanData.bytes;
    const float *background = _backgroundScanData.bytes;
    const float *displayScan = _displayScanData.bytes;
    const float *displayTrace = _displayPointTraceData.bytes;
    float selectedVoltage = [_loadedFile voltageAtPoint:_selectedPointIndex];
    double selectedTimeSeq = [_loadedFile sequenceTimeSecondsAtScan:_selectedScanIndex];
    double selectedTimeExp = [_loadedFile experimentTimeSecondsAtScan:_selectedScanIndex];
    double backgroundTimeSeq = [_loadedFile sequenceTimeSecondsAtScan:_backgroundScanIndex];
    double backgroundTimeExp = [_loadedFile experimentTimeSecondsAtScan:_backgroundScanIndex];
    float rawCurrent = selectedRaw[_selectedPointIndex];
    float backgroundCurrent = background[_selectedPointIndex];
    float displayCurrent = displayScan[_selectedPointIndex];

    _selectionHeadlineLabel.stringValue = [NSString stringWithFormat:@"Scan %lu • Point %lu • %.3f V",
                                           (unsigned long)_selectedScanIndex,
                                           (unsigned long)_selectedPointIndex,
                                           selectedVoltage];
    _selectionDetail1Label.stringValue = [NSString stringWithFormat:@"Sequence %.3f s • Experiment %.3f s • Within scan %.3f ms",
                                          selectedTimeSeq,
                                          selectedTimeExp,
                                          [_loadedFile withinScanTimeSecondsAtPoint:_selectedPointIndex] * 1000.0];
    _selectionDetail2Label.stringValue = [NSString stringWithFormat:@"Raw current %.3f • Background current %.3f • Display current %.3f",
                                          rawCurrent,
                                          backgroundCurrent,
                                          displayCurrent];
    _selectionDetail3Label.stringValue = [NSString stringWithFormat:@"Background scan %lu • Sequence %.3f s • Experiment %.3f s",
                                          (unsigned long)_backgroundScanIndex,
                                          backgroundTimeSeq,
                                          backgroundTimeExp];
    if (_displayPointTraceData.length >= _loadedFile.scanCount * sizeof(float)) {
        _selectionDetail4Label.stringValue = [NSString stringWithFormat:@"I-t sample at selected point: %.3f (%@)",
                                              displayTrace[_selectedScanIndex],
                                              [self displayModeText]];
    } else {
        _selectionDetail4Label.stringValue = @"I-t trace is being computed for the selected voltage point.";
    }

    _scanControlLabel.stringValue = [NSString stringWithFormat:@"Selected scan: %lu of %u",
                                     (unsigned long)_selectedScanIndex,
                                     _loadedFile.scanCount - 1U];
    _pointControlLabel.stringValue = [NSString stringWithFormat:@"Selected voltage point: %lu of %u",
                                      (unsigned long)_selectedPointIndex,
                                      _loadedFile.pointsPerScan - 1U];
    _backgroundControlLabel.stringValue = [NSString stringWithFormat:@"Background scan: %lu of %u",
                                           (unsigned long)_backgroundScanIndex,
                                           _loadedFile.scanCount - 1U];
}

- (void)requestPointTraceRefresh
{
    if (_loadedFile == nil) {
        return;
    }

    NSUInteger requestToken = ++_traceRequestToken;
    NSUInteger pointIndex = _selectedPointIndex;
    HDCVLoadedFile *loadedFile = _loadedFile;
    _heroStatusLabel.stringValue = [NSString stringWithFormat:@"Extracting I-t trace for waveform point %lu…", (unsigned long)pointIndex];

    dispatch_async(_workerQueue, ^{
        NSMutableData *traceData = [NSMutableData dataWithLength:(NSUInteger)loadedFile.scanCount * sizeof(float)];
        float traceMin = 0.0f;
        float traceMax = 0.0f;
        BOOL ok = [loadedFile copyPointTraceAtIndex:(uint32_t)pointIndex intoMutableData:traceData min:&traceMin max:&traceMax];
        (void)traceMin;
        (void)traceMax;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (requestToken != self->_traceRequestToken || loadedFile != self->_loadedFile) {
                return;
            }
            if (!ok) {
                self->_heroStatusLabel.stringValue = @"Failed to compute the I-t trace for the selected point.";
                return;
            }
            self->_rawPointTraceData = traceData;
            [self applyDisplayModes];
            [self refreshSelectionReadout];
            self->_heroStatusLabel.stringValue = @"Interactive FSCV plots are live. Use the color plot, I-t plot, CV plot, or sliders to move crosshairs and select a background.";
        });
    });
}

- (void)openOrRefreshAfterSelectionChangeNeedsTrace:(BOOL)needsTrace
{
    if (_loadedFile == nil) {
        return;
    }

    if (![self copySelectedScan]) {
        return;
    }
    [self applyDisplayModes];
    [self refreshSelectionReadout];

    if (needsTrace) {
        [self requestPointTraceRefresh];
    }
}

- (void)scanSliderChanged:(id)sender
{
    (void)sender;
    if (_loadedFile == nil) {
        return;
    }
    _selectedScanIndex = (NSUInteger)llround(_scanSlider.doubleValue);
    _scanSlider.doubleValue = (double)_selectedScanIndex;
    [self openOrRefreshAfterSelectionChangeNeedsTrace:NO];
}

- (void)pointSliderChanged:(id)sender
{
    (void)sender;
    if (_loadedFile == nil) {
        return;
    }
    _selectedPointIndex = (NSUInteger)llround(_pointSlider.doubleValue);
    _pointSlider.doubleValue = (double)_selectedPointIndex;
    [self openOrRefreshAfterSelectionChangeNeedsTrace:YES];
}

- (void)backgroundSliderChanged:(id)sender
{
    (void)sender;
    if (_loadedFile == nil) {
        return;
    }
    _backgroundScanIndex = (NSUInteger)llround(_backgroundSlider.doubleValue);
    _backgroundSlider.doubleValue = (double)_backgroundScanIndex;
    [self copyBackgroundScan];
    [self applyDisplayModes];
    [self rebuildHeatmapImage];
    [self refreshSelectionReadout];
    _heroStatusLabel.stringValue = [NSString stringWithFormat:@"Background scan set to %lu.", (unsigned long)_backgroundScanIndex];
}

- (void)backgroundSubtractToggled:(id)sender
{
    (void)sender;
    if (_loadedFile == nil) {
        return;
    }
    _backgroundSubtractEnabled = (_backgroundSubtractCheckbox.state == NSControlStateValueOn);
    [self applyDisplayModes];
    [self rebuildHeatmapImage];
    [self refreshSelectionReadout];
    _heroStatusLabel.stringValue = _backgroundSubtractEnabled
        ? @"Background subtraction is enabled across the color plot, I-t plot, and CV plot."
        : @"Background subtraction is disabled. The plots are showing raw current.";
}

- (void)useSelectedScanAsBackground:(id)sender
{
    (void)sender;
    if (_loadedFile == nil) {
        return;
    }
    _backgroundScanIndex = _selectedScanIndex;
    _backgroundSlider.doubleValue = (double)_backgroundScanIndex;
    [self copyBackgroundScan];
    [self applyDisplayModes];
    [self rebuildHeatmapImage];
    [self refreshSelectionReadout];
    _heroStatusLabel.stringValue = [NSString stringWithFormat:@"Background scan updated to the selected scan %lu.", (unsigned long)_backgroundScanIndex];
}

- (void)timeAxisModeChanged:(id)sender
{
    (void)sender;
    if (_loadedFile == nil) {
        return;
    }
    [self refreshHeatmapTicks];
    [self refreshPlotTitles];
    [self refreshPlots];
    [self refreshSelectionReadout];
}

- (void)heatmapView:(HDCVHeatmapView *)view didSelectScanIndex:(NSUInteger)scanIndex pointIndex:(NSUInteger)pointIndex
{
    (void)view;
    if (_loadedFile == nil) {
        return;
    }
    _selectedScanIndex = MIN(scanIndex, _loadedFile.scanCount - 1U);
    _selectedPointIndex = MIN(pointIndex, _loadedFile.pointsPerScan - 1U);
    _scanSlider.doubleValue = (double)_selectedScanIndex;
    _pointSlider.doubleValue = (double)_selectedPointIndex;
    [self openOrRefreshAfterSelectionChangeNeedsTrace:YES];
}

- (void)linePlotView:(HDCVLinePlotView *)view didSelectXValue:(double)xValue
{
    if (_loadedFile == nil) {
        return;
    }

    if (view == _timePlotView) {
        NSUInteger bestScanIndex = 0U;
        double bestDistance = DBL_MAX;
        for (NSUInteger scanIndex = 0U; scanIndex < _loadedFile.scanCount; ++scanIndex) {
            double distance = fabs([self timeValueForScanIndex:scanIndex] - xValue);
            if (distance < bestDistance) {
                bestDistance = distance;
                bestScanIndex = scanIndex;
            }
        }
        _selectedScanIndex = bestScanIndex;
        _scanSlider.doubleValue = (double)_selectedScanIndex;
        [self openOrRefreshAfterSelectionChangeNeedsTrace:NO];
    } else if (view == _cvPlotView) {
        NSUInteger bestPointIndex = 0U;
        double bestDistance = DBL_MAX;
        for (NSUInteger pointIndex = 0U; pointIndex < _loadedFile.pointsPerScan; ++pointIndex) {
            double distance = fabs((double)[_loadedFile voltageAtPoint:pointIndex] - xValue);
            if (distance < bestDistance) {
                bestDistance = distance;
                bestPointIndex = pointIndex;
            }
        }
        _selectedPointIndex = bestPointIndex;
        _pointSlider.doubleValue = (double)_selectedPointIndex;
        [self openOrRefreshAfterSelectionChangeNeedsTrace:YES];
    }
}

- (NSUInteger)sampleCountForLinePlotView:(HDCVLinePlotView *)view
{
    if (_loadedFile == nil) {
        return 0U;
    }
    if (view == _timePlotView) {
        return _loadedFile.scanCount;
    }
    if (view == _cvPlotView) {
        return _loadedFile.pointsPerScan;
    }
    return 0U;
}

- (double)linePlotView:(HDCVLinePlotView *)view xValueAtIndex:(NSUInteger)index
{
    if (view == _timePlotView) {
        return [self timeValueForScanIndex:index];
    }
    if (view == _cvPlotView) {
        return [_loadedFile voltageAtPoint:index];
    }
    return 0.0;
}

- (double)linePlotView:(HDCVLinePlotView *)view yValueAtIndex:(NSUInteger)index
{
    if (view == _timePlotView) {
        const float *trace = _displayPointTraceData.bytes;
        return trace[index];
    }
    if (view == _cvPlotView) {
        const float *scan = _displayScanData.bytes;
        return scan[index];
    }
    return 0.0;
}

@end

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        NSApplication *application = [NSApplication sharedApplication];
        HDCVViewerController *controller = [[HDCVViewerController alloc] init];
        NSMutableArray<NSString *> *arguments = [NSMutableArray array];
        for (int i = 0; i < argc; ++i) {
            [arguments addObject:[NSString stringWithUTF8String:argv[i]]];
        }
        [controller setInitialPathFromArguments:arguments];
        application.delegate = controller;
        [application setActivationPolicy:NSApplicationActivationPolicyRegular];
        [application run];
    }
    return 0;
}
