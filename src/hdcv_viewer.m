#import <AppKit/AppKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#include "hdcv_analysis.h"

#include <string.h>

typedef NS_ENUM(NSInteger, HDCVTimeAxisMode) {
    HDCVTimeAxisModeSequence = 0,
    HDCVTimeAxisModeExperiment = 1,
};

@class HDCVHeatmapView;
@class HDCVLinePlotView;

@protocol HDCVHeatmapViewDelegate <NSObject>
- (void)heatmapView:(HDCVHeatmapView *)view didSelectScanIndex:(NSUInteger)scanIndex pointIndex:(NSUInteger)pointIndex;
@end

@protocol HDCVLinePlotDataSource <NSObject>
- (NSUInteger)sampleCountForLinePlotView:(HDCVLinePlotView *)view;
- (double)linePlotView:(HDCVLinePlotView *)view xValueAtIndex:(NSUInteger)index;
- (double)linePlotView:(HDCVLinePlotView *)view yValueAtIndex:(NSUInteger)index;
@end

@interface HDCVHeatmapView : NSView
@property(nonatomic, strong) NSImage *image;
@property(nonatomic, strong) NSData *voltageData;
@property(nonatomic, weak) id<HDCVHeatmapViewDelegate> delegate;
@property(nonatomic, copy) NSArray<NSString *> *xTickLabels;
@property(nonatomic, copy) NSArray<NSNumber *> *xTickFractions;
@property(nonatomic) NSUInteger selectedScanIndex;
@property(nonatomic) NSUInteger scanCount;
@property(nonatomic) NSUInteger selectedPointIndex;
@property(nonatomic) NSUInteger pointCount;
@property(nonatomic, copy) NSString *titleText;
@end

@interface HDCVLinePlotView : NSView
@property(nonatomic, weak) id<HDCVLinePlotDataSource> dataSource;
@property(nonatomic, copy) NSString *titleText;
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
@property(nonatomic) BOOL showsSelection;
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

@interface HDCVViewerController : NSObject <HDCVHeatmapViewDelegate, HDCVLinePlotDataSource, NSApplicationDelegate>
@end

static NSString *const HDCVViewerErrorDomain = @"com.openai.hdcvviewer";

static NSColor *HDCVPanelBackgroundColor(void)
{
    return [NSColor colorWithRed:0.98 green:0.985 blue:0.99 alpha:1.0];
}

static NSColor *HDCVPanelBorderColor(void)
{
    return [NSColor colorWithRed:0.84 green:0.87 blue:0.91 alpha:1.0];
}

static NSColor *HDCVAccentBlue(void)
{
    return [NSColor colorWithRed:0.11 green:0.39 blue:0.74 alpha:1.0];
}

static NSColor *HDCVAccentOrange(void)
{
    return [NSColor colorWithRed:0.86 green:0.39 blue:0.16 alpha:1.0];
}

static NSColor *HDCVMutedText(void)
{
    return [NSColor colorWithRed:0.34 green:0.39 blue:0.45 alpha:1.0];
}

static NSView *HDCVPanelContainer(void)
{
    NSView *view = [[NSView alloc] initWithFrame:NSZeroRect];
    view.translatesAutoresizingMaskIntoConstraints = NO;
    view.wantsLayer = YES;
    view.layer.backgroundColor = HDCVPanelBackgroundColor().CGColor;
    view.layer.borderColor = HDCVPanelBorderColor().CGColor;
    view.layer.borderWidth = 1.0;
    view.layer.cornerRadius = 14.0;
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

@implementation HDCVHeatmapView

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self != nil) {
        _titleText = @"Current Heatmap";
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
    return NSInsetRect(self.bounds, 54.0, 32.0);
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

- (NSDictionary<NSAttributedStringKey, id> *)labelAttributesWithColor:(NSColor *)color size:(CGFloat)size weight:(NSFontWeight)weight
{
    return @{
        NSFontAttributeName: [NSFont systemFontOfSize:size weight:weight],
        NSForegroundColorAttributeName: color
    };
}

- (void)drawRect:(NSRect)dirtyRect
{
    NSRect plotRect = [self plotRect];
    NSDictionary *titleAttrs = [self labelAttributesWithColor:NSColor.blackColor size:13.0 weight:NSFontWeightSemibold];
    NSDictionary *axisAttrs = [self labelAttributesWithColor:HDCVMutedText() size:10.0 weight:NSFontWeightRegular];
    NSDictionary *tickAttrs = [self labelAttributesWithColor:HDCVMutedText() size:9.0 weight:NSFontWeightRegular];

    [NSColor.whiteColor setFill];
    NSRectFill(self.bounds);

    [[NSColor colorWithWhite:0.94 alpha:1.0] setFill];
    NSRectFill(plotRect);

    [[NSColor colorWithWhite:0.84 alpha:1.0] setStroke];
    NSBezierPath *border = [NSBezierPath bezierPathWithRoundedRect:plotRect xRadius:8.0 yRadius:8.0];
    border.lineWidth = 1.0;
    [border stroke];

    [self.titleText drawAtPoint:NSMakePoint(plotRect.origin.x, 8.0) withAttributes:titleAttrs];

    if (self.image != nil) {
        [self.image drawInRect:plotRect];
    }

    if (self.scanCount > 0U && self.pointCount > 0U) {
        CGFloat xFraction = self.scanCount > 1U ? (CGFloat)self.selectedScanIndex / (CGFloat)(self.scanCount - 1U) : 0.0;
        CGFloat yFraction = self.pointCount > 1U ? (CGFloat)self.selectedPointIndex / (CGFloat)(self.pointCount - 1U) : 0.0;
        CGFloat crossX = plotRect.origin.x + (xFraction * plotRect.size.width);
        CGFloat crossY = plotRect.origin.y + plotRect.size.height - (yFraction * plotRect.size.height);

        [[NSColor colorWithRed:0.76 green:0.18 blue:0.16 alpha:0.95] setStroke];
        NSBezierPath *vertical = [NSBezierPath bezierPath];
        [vertical moveToPoint:NSMakePoint(crossX, plotRect.origin.y)];
        [vertical lineToPoint:NSMakePoint(crossX, NSMaxY(plotRect))];
        vertical.lineWidth = 1.3;
        CGFloat verticalDashes[] = {6.0, 4.0};
        [vertical setLineDash:verticalDashes count:2 phase:0.0];
        [vertical stroke];

        [[NSColor colorWithRed:0.09 green:0.44 blue:0.41 alpha:0.95] setStroke];
        NSBezierPath *horizontal = [NSBezierPath bezierPath];
        [horizontal moveToPoint:NSMakePoint(plotRect.origin.x, crossY)];
        [horizontal lineToPoint:NSMakePoint(NSMaxX(plotRect), crossY)];
        horizontal.lineWidth = 1.3;
        CGFloat horizontalDashes[] = {5.0, 4.0};
        [horizontal setLineDash:horizontalDashes count:2 phase:0.0];
        [horizontal stroke];
    }

    [@"Time" drawAtPoint:NSMakePoint(NSMidX(plotRect) - 14.0, NSMaxY(plotRect) + 8.0) withAttributes:axisAttrs];
    [@"Waveform / Voltage" drawAtPoint:NSMakePoint(8.0, 10.0) withAttributes:axisAttrs];

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
        NSUInteger tickCount = MIN((NSUInteger)5U, self.pointCount);
        for (NSUInteger i = 0U; i < tickCount; ++i) {
            NSUInteger pointIndex = tickCount == 1U ? 0U : (NSUInteger)llround((double)i * (double)(self.pointCount - 1U) / (double)(tickCount - 1U));
            CGFloat fraction = self.pointCount > 1U ? (CGFloat)pointIndex / (CGFloat)(self.pointCount - 1U) : 0.0;
            CGFloat y = plotRect.origin.y + plotRect.size.height - (fraction * plotRect.size.height);
            NSString *label = [NSString stringWithFormat:@"%.2f V", voltage[pointIndex]];
            NSSize size = [label sizeWithAttributes:tickAttrs];
            [label drawAtPoint:NSMakePoint(6.0, y - size.height * 0.5) withAttributes:tickAttrs];

            [[NSColor colorWithWhite:0.88 alpha:1.0] setStroke];
            NSBezierPath *grid = [NSBezierPath bezierPath];
            [grid moveToPoint:NSMakePoint(plotRect.origin.x, y)];
            [grid lineToPoint:NSMakePoint(NSMaxX(plotRect), y)];
            grid.lineWidth = 0.5;
            [grid stroke];
        }
    }
}

- (void)mouseDown:(NSEvent *)event
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

@end

@implementation HDCVLinePlotView

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self != nil) {
        _strokeColor = HDCVAccentBlue();
        _xTickFormat = @"%.2f";
        _yTickFormat = @"%.2f";
        _titleText = @"Plot";
        _xLabelText = @"X";
        _yLabelText = @"Y";
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
    return NSInsetRect(self.bounds, 52.0, 34.0);
}

- (NSDictionary<NSAttributedStringKey, id> *)labelAttributesWithColor:(NSColor *)color size:(CGFloat)size weight:(NSFontWeight)weight
{
    return @{
        NSFontAttributeName: [NSFont systemFontOfSize:size weight:weight],
        NSForegroundColorAttributeName: color
    };
}

- (void)drawRect:(NSRect)dirtyRect
{
    NSRect plotRect = [self plotRect];
    NSUInteger sampleCount = [self.dataSource sampleCountForLinePlotView:self];
    NSDictionary *titleAttrs = [self labelAttributesWithColor:NSColor.blackColor size:13.0 weight:NSFontWeightSemibold];
    NSDictionary *axisAttrs = [self labelAttributesWithColor:HDCVMutedText() size:10.0 weight:NSFontWeightRegular];
    NSDictionary *tickAttrs = [self labelAttributesWithColor:HDCVMutedText() size:9.0 weight:NSFontWeightRegular];

    (void)dirtyRect;
    [NSColor.whiteColor setFill];
    NSRectFill(self.bounds);

    [[NSColor colorWithWhite:0.95 alpha:1.0] setFill];
    NSRectFill(plotRect);

    [[NSColor colorWithWhite:0.84 alpha:1.0] setStroke];
    NSBezierPath *border = [NSBezierPath bezierPathWithRoundedRect:plotRect xRadius:8.0 yRadius:8.0];
    border.lineWidth = 1.0;
    [border stroke];

    [self.titleText drawAtPoint:NSMakePoint(plotRect.origin.x, 8.0) withAttributes:titleAttrs];
    [self.xLabelText drawAtPoint:NSMakePoint(NSMidX(plotRect) - 12.0, NSMaxY(plotRect) + 8.0) withAttributes:axisAttrs];
    [self.yLabelText drawAtPoint:NSMakePoint(8.0, 10.0) withAttributes:axisAttrs];

    if (sampleCount == 0U || self.xMax <= self.xMin || self.yMax <= self.yMin) {
        return;
    }

    for (NSUInteger tick = 0U; tick < 5U; ++tick) {
        CGFloat fraction = (CGFloat)tick / 4.0;
        double xValue = self.xMin + ((self.xMax - self.xMin) * fraction);
        double yValue = self.yMax - ((self.yMax - self.yMin) * fraction);
        NSString *xLabel = [NSString stringWithFormat:self.xTickFormat, xValue];
        NSString *yLabel = [NSString stringWithFormat:self.yTickFormat, yValue];
        NSSize xSize = [xLabel sizeWithAttributes:tickAttrs];
        NSSize ySize = [yLabel sizeWithAttributes:tickAttrs];
        CGFloat x = plotRect.origin.x + (fraction * plotRect.size.width);
        CGFloat y = plotRect.origin.y + (fraction * plotRect.size.height);

        [[NSColor colorWithWhite:0.89 alpha:1.0] setStroke];
        NSBezierPath *gridV = [NSBezierPath bezierPath];
        [gridV moveToPoint:NSMakePoint(x, plotRect.origin.y)];
        [gridV lineToPoint:NSMakePoint(x, NSMaxY(plotRect))];
        gridV.lineWidth = 0.5;
        [gridV stroke];

        NSBezierPath *gridH = [NSBezierPath bezierPath];
        [gridH moveToPoint:NSMakePoint(plotRect.origin.x, y)];
        [gridH lineToPoint:NSMakePoint(NSMaxX(plotRect), y)];
        gridH.lineWidth = 0.5;
        [gridH stroke];

        [xLabel drawAtPoint:NSMakePoint(x - xSize.width * 0.5, NSMaxY(plotRect) + 20.0) withAttributes:tickAttrs];
        [yLabel drawAtPoint:NSMakePoint(6.0, y - ySize.height * 0.5) withAttributes:tickAttrs];
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
    path.lineWidth = 1.8;

    for (NSUInteger i = 0U; i < sampleCount; i += step) {
        double xValue = [self.dataSource linePlotView:self xValueAtIndex:i];
        double yValue = [self.dataSource linePlotView:self yValueAtIndex:i];
        CGFloat x = plotRect.origin.x + (CGFloat)((xValue - self.xMin) / (self.xMax - self.xMin)) * plotRect.size.width;
        CGFloat y = plotRect.origin.y + plotRect.size.height - (CGFloat)((yValue - self.yMin) / (self.yMax - self.yMin)) * plotRect.size.height;
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
        CGFloat x = plotRect.origin.x + (CGFloat)((xValue - self.xMin) / (self.xMax - self.xMin)) * plotRect.size.width;
        CGFloat y = plotRect.origin.y + plotRect.size.height - (CGFloat)((yValue - self.yMin) / (self.yMax - self.yMin)) * plotRect.size.height;
        [path lineToPoint:NSMakePoint(x, y)];
    }
    [path stroke];

    if (self.showsSelection) {
        CGFloat x = plotRect.origin.x + (CGFloat)((self.selectedXValue - self.xMin) / (self.xMax - self.xMin)) * plotRect.size.width;
        CGFloat y = plotRect.origin.y + plotRect.size.height - (CGFloat)((self.selectedYValue - self.yMin) / (self.yMax - self.yMin)) * plotRect.size.height;

        [[NSColor colorWithRed:0.76 green:0.18 blue:0.16 alpha:0.95] setStroke];
        NSBezierPath *vertical = [NSBezierPath bezierPath];
        [vertical moveToPoint:NSMakePoint(x, plotRect.origin.y)];
        [vertical lineToPoint:NSMakePoint(x, NSMaxY(plotRect))];
        vertical.lineWidth = 1.2;
        CGFloat dashes[] = {5.0, 4.0};
        [vertical setLineDash:dashes count:2 phase:0.0];
        [vertical stroke];

        [[NSColor colorWithRed:0.09 green:0.44 blue:0.41 alpha:0.95] setFill];
        NSRect markerRect = NSMakeRect(x - 3.5, y - 3.5, 7.0, 7.0);
        NSBezierPath *marker = [NSBezierPath bezierPathWithOvalInRect:markerRect];
        [marker fill];
    }
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
            *error = [NSError errorWithDomain:HDCVViewerErrorDomain code:1 userInfo:@{
                NSLocalizedDescriptionKey: [NSString stringWithUTF8String:_reader.error]
            }];
        }
        return nil;
    }
    _isOpen = YES;

    NSMutableData *voltageBuffer = [NSMutableData dataWithLength:(NSUInteger)_reader.layout.points_per_scan * sizeof(float)];
    if (!hdcv_reader_copy_voltage(&_reader, voltageBuffer.mutableBytes, _reader.layout.points_per_scan)) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:HDCVViewerErrorDomain code:2 userInfo:@{
                NSLocalizedDescriptionKey: @"Failed to copy active voltage waveform."
            }];
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
                *error = [NSError errorWithDomain:HDCVViewerErrorDomain code:3 userInfo:@{
                    NSLocalizedDescriptionKey: @"Failed to build overview heatmap."
                }];
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
    HDCVHeatmapView *_heatmapView;
    HDCVLinePlotView *_timePlotView;
    HDCVLinePlotView *_cvPlotView;
    NSTextField *_fileLabel;
    NSTextField *_statusLabel;
    NSTextField *_scanLabel;
    NSTextField *_pointLabel;
    NSTextView *_infoTextView;
    NSScrollView *_infoScrollView;
    NSSlider *_scanSlider;
    NSSlider *_pointSlider;
    NSSegmentedControl *_timeAxisControl;
    NSProgressIndicator *_progressIndicator;
    HDCVLoadedFile *_loadedFile;
    NSMutableData *_currentScanData;
    NSMutableData *_currentTraceData;
    float _currentScanMin;
    float _currentScanMax;
    float _currentTraceMin;
    float _currentTraceMax;
    NSUInteger _selectedScanIndex;
    NSUInteger _selectedPointIndex;
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
    }
    return self;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    (void)notification;
    [self buildWindow];
    [_window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];

    if (_pendingOpenPath != nil) {
        [self loadFileAtPath:_pendingOpenPath];
    }
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
    (void)sender;
    return YES;
}

- (void)setInitialPathFromArguments:(NSArray<NSString *> *)arguments
{
    if (arguments.count > 1U) {
        _pendingOpenPath = arguments[1];
    }
}

- (void)buildWindow
{
    _window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 1560.0, 960.0)
                                          styleMask:(NSWindowStyleMaskTitled |
                                                     NSWindowStyleMaskClosable |
                                                     NSWindowStyleMaskResizable |
                                                     NSWindowStyleMaskMiniaturizable)
                                            backing:NSBackingStoreBuffered
                                              defer:NO];
    _window.title = @"HDCV Viewer";
    _window.minSize = NSMakeSize(1280.0, 800.0);
    _window.backgroundColor = [NSColor colorWithRed:0.94 green:0.955 blue:0.97 alpha:1.0];

    NSView *contentView = _window.contentView;
    contentView.wantsLayer = YES;
    contentView.layer.backgroundColor = [NSColor colorWithRed:0.94 green:0.955 blue:0.97 alpha:1.0].CGColor;

    NSStackView *rootStack = [[NSStackView alloc] init];
    rootStack.translatesAutoresizingMaskIntoConstraints = NO;
    rootStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    rootStack.spacing = 14.0;
    [contentView addSubview:rootStack];

    [NSLayoutConstraint activateConstraints:@[
        [rootStack.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:18.0],
        [rootStack.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-18.0],
        [rootStack.topAnchor constraintEqualToAnchor:contentView.topAnchor constant:18.0],
        [rootStack.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor constant:-18.0],
    ]];

    NSView *headerPanel = HDCVPanelContainer();
    [rootStack addArrangedSubview:headerPanel];
    [headerPanel.heightAnchor constraintEqualToConstant:74.0].active = YES;

    NSButton *openButton = [NSButton buttonWithTitle:@"Open HDCV File" target:self action:@selector(openDocument:)];
    openButton.translatesAutoresizingMaskIntoConstraints = NO;
    openButton.bezelStyle = NSBezelStyleRounded;
    openButton.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightSemibold];
    [headerPanel addSubview:openButton];

    _fileLabel = HDCVLabel(@"No file loaded", [NSFont systemFontOfSize:14.0 weight:NSFontWeightSemibold], NSColor.blackColor);
    [headerPanel addSubview:_fileLabel];

    _statusLabel = HDCVLabel(@"Open an HDCV file to build the verified overview and plots.", [NSFont systemFontOfSize:11.0 weight:NSFontWeightRegular], HDCVMutedText());
    [headerPanel addSubview:_statusLabel];

    _timeAxisControl = [[NSSegmentedControl alloc] initWithFrame:NSZeroRect];
    _timeAxisControl.translatesAutoresizingMaskIntoConstraints = NO;
    _timeAxisControl.segmentCount = 2;
    [_timeAxisControl setLabel:@"Sequence" forSegment:0];
    [_timeAxisControl setLabel:@"Experiment" forSegment:1];
    _timeAxisControl.trackingMode = NSSegmentSwitchTrackingSelectOne;
    _timeAxisControl.target = self;
    _timeAxisControl.action = @selector(timeAxisModeChanged:);
    _timeAxisControl.selectedSegment = 0;
    [headerPanel addSubview:_timeAxisControl];

    _progressIndicator = [[NSProgressIndicator alloc] init];
    _progressIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    _progressIndicator.style = NSProgressIndicatorStyleSpinning;
    _progressIndicator.controlSize = NSControlSizeRegular;
    _progressIndicator.displayedWhenStopped = NO;
    [headerPanel addSubview:_progressIndicator];

    [NSLayoutConstraint activateConstraints:@[
        [openButton.leadingAnchor constraintEqualToAnchor:headerPanel.leadingAnchor constant:16.0],
        [openButton.topAnchor constraintEqualToAnchor:headerPanel.topAnchor constant:18.0],
        [_fileLabel.leadingAnchor constraintEqualToAnchor:openButton.trailingAnchor constant:18.0],
        [_fileLabel.topAnchor constraintEqualToAnchor:headerPanel.topAnchor constant:16.0],
        [_statusLabel.leadingAnchor constraintEqualToAnchor:_fileLabel.leadingAnchor],
        [_statusLabel.topAnchor constraintEqualToAnchor:_fileLabel.bottomAnchor constant:6.0],
        [_timeAxisControl.trailingAnchor constraintEqualToAnchor:headerPanel.trailingAnchor constant:-18.0],
        [_timeAxisControl.centerYAnchor constraintEqualToAnchor:headerPanel.centerYAnchor],
        [_progressIndicator.trailingAnchor constraintEqualToAnchor:_timeAxisControl.leadingAnchor constant:-16.0],
        [_progressIndicator.centerYAnchor constraintEqualToAnchor:_timeAxisControl.centerYAnchor],
    ]];

    NSStackView *contentStack = [[NSStackView alloc] init];
    contentStack.translatesAutoresizingMaskIntoConstraints = NO;
    contentStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    contentStack.spacing = 14.0;
    [rootStack addArrangedSubview:contentStack];

    NSStackView *mainColumn = [[NSStackView alloc] init];
    mainColumn.translatesAutoresizingMaskIntoConstraints = NO;
    mainColumn.orientation = NSUserInterfaceLayoutOrientationVertical;
    mainColumn.spacing = 14.0;
    [contentStack addArrangedSubview:mainColumn];

    NSView *heatmapPanel = HDCVPanelContainer();
    [mainColumn addArrangedSubview:heatmapPanel];
    [heatmapPanel.heightAnchor constraintGreaterThanOrEqualToConstant:360.0].active = YES;

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

    NSView *controlsPanel = HDCVPanelContainer();
    [mainColumn addArrangedSubview:controlsPanel];
    [controlsPanel.heightAnchor constraintEqualToConstant:118.0].active = YES;

    _scanLabel = HDCVLabel(@"Scan: -", [NSFont systemFontOfSize:12.0 weight:NSFontWeightSemibold], NSColor.blackColor);
    _pointLabel = HDCVLabel(@"Point: -", [NSFont systemFontOfSize:12.0 weight:NSFontWeightSemibold], NSColor.blackColor);
    _scanSlider = [[NSSlider alloc] init];
    _pointSlider = [[NSSlider alloc] init];
    _scanSlider.translatesAutoresizingMaskIntoConstraints = NO;
    _pointSlider.translatesAutoresizingMaskIntoConstraints = NO;
    _scanSlider.target = self;
    _scanSlider.action = @selector(scanSliderChanged:);
    _scanSlider.continuous = YES;
    _pointSlider.target = self;
    _pointSlider.action = @selector(pointSliderChanged:);
    _pointSlider.continuous = NO;
    _scanSlider.enabled = NO;
    _pointSlider.enabled = NO;
    [controlsPanel addSubview:_scanLabel];
    [controlsPanel addSubview:_pointLabel];
    [controlsPanel addSubview:_scanSlider];
    [controlsPanel addSubview:_pointSlider];

    [NSLayoutConstraint activateConstraints:@[
        [_scanLabel.leadingAnchor constraintEqualToAnchor:controlsPanel.leadingAnchor constant:16.0],
        [_scanLabel.topAnchor constraintEqualToAnchor:controlsPanel.topAnchor constant:16.0],
        [_scanSlider.leadingAnchor constraintEqualToAnchor:controlsPanel.leadingAnchor constant:16.0],
        [_scanSlider.trailingAnchor constraintEqualToAnchor:controlsPanel.trailingAnchor constant:-16.0],
        [_scanSlider.topAnchor constraintEqualToAnchor:_scanLabel.bottomAnchor constant:8.0],
        [_pointLabel.leadingAnchor constraintEqualToAnchor:controlsPanel.leadingAnchor constant:16.0],
        [_pointLabel.topAnchor constraintEqualToAnchor:_scanSlider.bottomAnchor constant:14.0],
        [_pointSlider.leadingAnchor constraintEqualToAnchor:controlsPanel.leadingAnchor constant:16.0],
        [_pointSlider.trailingAnchor constraintEqualToAnchor:controlsPanel.trailingAnchor constant:-16.0],
        [_pointSlider.topAnchor constraintEqualToAnchor:_pointLabel.bottomAnchor constant:8.0],
    ]];

    NSStackView *plotRow = [[NSStackView alloc] init];
    plotRow.translatesAutoresizingMaskIntoConstraints = NO;
    plotRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    plotRow.spacing = 14.0;
    [mainColumn addArrangedSubview:plotRow];

    NSView *timePanel = HDCVPanelContainer();
    NSView *cvPanel = HDCVPanelContainer();
    [plotRow addArrangedSubview:timePanel];
    [plotRow addArrangedSubview:cvPanel];
    [timePanel.widthAnchor constraintEqualToAnchor:cvPanel.widthAnchor].active = YES;
    [timePanel.heightAnchor constraintGreaterThanOrEqualToConstant:250.0].active = YES;
    [cvPanel.heightAnchor constraintGreaterThanOrEqualToConstant:250.0].active = YES;

    _timePlotView = [[HDCVLinePlotView alloc] initWithFrame:NSZeroRect];
    _timePlotView.translatesAutoresizingMaskIntoConstraints = NO;
    _timePlotView.dataSource = self;
    _timePlotView.titleText = @"Current vs Time";
    _timePlotView.xLabelText = @"Time (s)";
    _timePlotView.yLabelText = @"Current";
    _timePlotView.strokeColor = HDCVAccentBlue();
    [timePanel addSubview:_timePlotView];

    _cvPlotView = [[HDCVLinePlotView alloc] initWithFrame:NSZeroRect];
    _cvPlotView.translatesAutoresizingMaskIntoConstraints = NO;
    _cvPlotView.dataSource = self;
    _cvPlotView.titleText = @"Cyclic Voltammogram";
    _cvPlotView.xLabelText = @"Voltage (V)";
    _cvPlotView.yLabelText = @"Current";
    _cvPlotView.strokeColor = HDCVAccentOrange();
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

    NSView *infoPanel = HDCVPanelContainer();
    [contentStack addArrangedSubview:infoPanel];
    [infoPanel.widthAnchor constraintEqualToConstant:360.0].active = YES;

    NSTextField *infoTitle = HDCVLabel(@"File Summary and Metadata", [NSFont systemFontOfSize:13.0 weight:NSFontWeightSemibold], NSColor.blackColor);
    [infoPanel addSubview:infoTitle];

    _infoTextView = [[NSTextView alloc] initWithFrame:NSZeroRect];
    _infoTextView.editable = NO;
    _infoTextView.selectable = YES;
    _infoTextView.font = [NSFont monospacedSystemFontOfSize:11.0 weight:NSFontWeightRegular];
    _infoTextView.textColor = [NSColor colorWithRed:0.18 green:0.22 blue:0.28 alpha:1.0];
    _infoTextView.backgroundColor = NSColor.clearColor;
    _infoTextView.string = @"No file loaded.";

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

- (void)loadFileAtPath:(NSString *)path
{
    _pendingOpenPath = path;
    _scanSlider.enabled = NO;
    _pointSlider.enabled = NO;
    _fileLabel.stringValue = path.lastPathComponent;
    _statusLabel.stringValue = @"Loading file, validating layout, and building the overview heatmap…";
    [_progressIndicator startAnimation:nil];

    dispatch_async(_workerQueue, ^{
        NSError *error = nil;
        HDCVLoadedFile *loaded = [[HDCVLoadedFile alloc] initWithPath:path maxOverviewColumns:1400U error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self->_progressIndicator stopAnimation:nil];
            if (loaded == nil) {
                self->_statusLabel.stringValue = (error.localizedDescription != nil) ? error.localizedDescription : @"Failed to load file.";
                NSAlert *alert = [[NSAlert alloc] init];
                alert.alertStyle = NSAlertStyleWarning;
                alert.messageText = @"Failed to open HDCV file";
                alert.informativeText = (error.localizedDescription != nil) ? error.localizedDescription : @"Unknown error.";
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
    _currentScanData = [NSMutableData dataWithLength:(NSUInteger)loaded.pointsPerScan * sizeof(float)];
    _currentTraceData = [NSMutableData dataWithLength:(NSUInteger)loaded.scanCount * sizeof(float)];
    _selectedScanIndex = loaded.scanCount / 2U;
    _selectedPointIndex = loaded.pointsPerScan / 2U;

    _scanSlider.enabled = YES;
    _pointSlider.enabled = YES;
    _scanSlider.minValue = 0.0;
    _scanSlider.maxValue = (double)(loaded.scanCount - 1U);
    _scanSlider.doubleValue = (double)_selectedScanIndex;
    _pointSlider.minValue = 0.0;
    _pointSlider.maxValue = (double)(loaded.pointsPerScan - 1U);
    _pointSlider.doubleValue = (double)_selectedPointIndex;

    _heatmapView.scanCount = loaded.scanCount;
    _heatmapView.pointCount = loaded.pointsPerScan;
    _heatmapView.voltageData = loaded.voltageData;
    _heatmapView.image = [self buildHeatmapImageFromLoadedFile:loaded];

    [self refreshHeatmapTicks];
    [self refreshCurrentScan];
    [self requestPointTraceRefresh];

    _fileLabel.stringValue = [NSString stringWithFormat:@"%@  |  %u scans x %u points", _pendingOpenPath.lastPathComponent, loaded.scanCount, loaded.pointsPerScan];
}

- (NSImage *)buildHeatmapImageFromLoadedFile:(HDCVLoadedFile *)loaded
{
    NSUInteger width = loaded.overviewColumnCount;
    NSUInteger height = loaded.pointsPerScan;
    const float *values = loaded.overviewData.bytes;
    NSMutableData *pixelData = [NSMutableData dataWithLength:width * height * 4U];
    unsigned char *pixels = pixelData.mutableBytes;
    float minValue = loaded.overviewMinValue;
    float maxValue = loaded.overviewMaxValue;
    float center = 0.0f;
    float scale = MAX(fabsf(maxValue - center), fabsf(minValue - center));
    if (scale < 1.0e-9f) {
        scale = 1.0f;
    }

    for (NSUInteger pointIndex = 0U; pointIndex < height; ++pointIndex) {
        NSUInteger y = height - 1U - pointIndex;
        for (NSUInteger x = 0U; x < width; ++x) {
            float value = values[pointIndex * width + x];
            float normalized = MAX(-1.0f, MIN(1.0f, value / scale));
            float t = (normalized + 1.0f) * 0.5f;
            NSUInteger offset = (y * width + x) * 4U;
            float r;
            float g;
            float b;

            if (t < 0.25f) {
                float local = t / 0.25f;
                r = 0.05f + local * 0.05f;
                g = 0.12f + local * 0.45f;
                b = 0.32f + local * 0.48f;
            } else if (t < 0.5f) {
                float local = (t - 0.25f) / 0.25f;
                r = 0.10f + local * 0.10f;
                g = 0.57f + local * 0.27f;
                b = 0.80f - local * 0.35f;
            } else if (t < 0.75f) {
                float local = (t - 0.5f) / 0.25f;
                r = 0.20f + local * 0.58f;
                g = 0.84f + local * 0.08f;
                b = 0.45f - local * 0.32f;
            } else {
                float local = (t - 0.75f) / 0.25f;
                r = 0.78f + local * 0.16f;
                g = 0.92f - local * 0.54f;
                b = 0.13f - local * 0.06f;
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
        NSUInteger scanIndex = tickCount == 1U ? 0U : (NSUInteger)llround((double)i * (double)(scanCount - 1U) / (double)(tickCount - 1U));
        double timeValue = _timeAxisControl.selectedSegment == HDCVTimeAxisModeExperiment
            ? [_loadedFile experimentTimeSecondsAtScan:scanIndex]
            : [_loadedFile sequenceTimeSecondsAtScan:scanIndex];
        [labels addObject:[NSString stringWithFormat:@"%.1f s", timeValue]];
        [fractions addObject:@(scanCount > 1U ? (double)scanIndex / (double)(scanCount - 1U) : 0.0)];
    }
    _heatmapView.xTickLabels = labels;
    _heatmapView.xTickFractions = fractions;
}

- (void)refreshCurrentScan
{
    if (_loadedFile == nil) {
        return;
    }

    if (![_loadedFile copyScanAtIndex:(uint32_t)_selectedScanIndex intoMutableData:_currentScanData min:&_currentScanMin max:&_currentScanMax]) {
        return;
    }

    _heatmapView.selectedScanIndex = _selectedScanIndex;
    _heatmapView.selectedPointIndex = _selectedPointIndex;

    double selectedTime = [self selectedScanTime];
    float selectedCurrent = ((const float *)_currentScanData.bytes)[_selectedPointIndex];
    float selectedVoltage = [_loadedFile voltageAtPoint:_selectedPointIndex];

    _cvPlotView.xMin = -0.45;
    _cvPlotView.xMax = 1.15;
    _cvPlotView.yMin = (double)_currentScanMin;
    _cvPlotView.yMax = (double)_currentScanMax + 1.0e-6;
    _cvPlotView.selectedXValue = selectedVoltage;
    _cvPlotView.selectedYValue = selectedCurrent;
    _cvPlotView.showsSelection = YES;
    [_cvPlotView setNeedsDisplay:YES];

    if (_currentTraceData.length >= _loadedFile.scanCount * sizeof(float)) {
        const float *trace = _currentTraceData.bytes;
        if (_selectedScanIndex < _loadedFile.scanCount) {
            _timePlotView.selectedXValue = selectedTime;
            _timePlotView.selectedYValue = trace[_selectedScanIndex];
            _timePlotView.showsSelection = YES;
            [_timePlotView setNeedsDisplay:YES];
        }
    }

    _scanLabel.stringValue = [NSString stringWithFormat:
        @"Scan %lu / %u  |  Sequence %.3f s  |  Experiment %.3f s",
        (unsigned long)_selectedScanIndex,
        _loadedFile.scanCount - 1U,
        [_loadedFile sequenceTimeSecondsAtScan:_selectedScanIndex],
        [_loadedFile experimentTimeSecondsAtScan:_selectedScanIndex]
    ];

    _pointLabel.stringValue = [NSString stringWithFormat:
        @"Point %lu / %u  |  Voltage %.3f V  |  Within scan %.3f ms  |  Current %.3f",
        (unsigned long)_selectedPointIndex,
        _loadedFile.pointsPerScan - 1U,
        selectedVoltage,
        [_loadedFile withinScanTimeSecondsAtPoint:_selectedPointIndex] * 1000.0,
        selectedCurrent
    ];

    _statusLabel.stringValue = @"Layout verified. Heatmap, time trace, and cyclic voltammogram are live.";
}

- (double)selectedScanTime
{
    if (_loadedFile == nil) {
        return 0.0;
    }
    if (_timeAxisControl.selectedSegment == HDCVTimeAxisModeExperiment) {
        return [_loadedFile experimentTimeSecondsAtScan:_selectedScanIndex];
    }
    return [_loadedFile sequenceTimeSecondsAtScan:_selectedScanIndex];
}

- (void)requestPointTraceRefresh
{
    if (_loadedFile == nil) {
        return;
    }

    NSUInteger requestToken = ++_traceRequestToken;
    NSUInteger pointIndex = _selectedPointIndex;
    HDCVLoadedFile *loadedFile = _loadedFile;
    _statusLabel.stringValue = [NSString stringWithFormat:@"Computing current-vs-time trace for point %lu…", (unsigned long)pointIndex];

    dispatch_async(_workerQueue, ^{
        NSMutableData *traceData = [NSMutableData dataWithLength:(NSUInteger)loadedFile.scanCount * sizeof(float)];
        float traceMin = 0.0f;
        float traceMax = 0.0f;
        BOOL ok = [loadedFile copyPointTraceAtIndex:(uint32_t)pointIndex intoMutableData:traceData min:&traceMin max:&traceMax];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (requestToken != self->_traceRequestToken || loadedFile != self->_loadedFile) {
                return;
            }
            if (!ok) {
                self->_statusLabel.stringValue = @"Failed to compute the selected point trace.";
                return;
            }
            self->_currentTraceData = traceData;
            self->_currentTraceMin = traceMin;
            self->_currentTraceMax = traceMax;
            [self refreshTimePlot];
            [self refreshCurrentScan];
        });
    });
}

- (void)refreshTimePlot
{
    if (_loadedFile == nil || _currentTraceData.length < _loadedFile.scanCount * sizeof(float)) {
        return;
    }

    _timePlotView.xMin = [self timeValueForScanIndex:0U];
    _timePlotView.xMax = [self timeValueForScanIndex:_loadedFile.scanCount - 1U];
    _timePlotView.yMin = (double)_currentTraceMin;
    _timePlotView.yMax = (double)_currentTraceMax + 1.0e-6;
    _timePlotView.selectedXValue = [self selectedScanTime];
    _timePlotView.selectedYValue = ((const float *)_currentTraceData.bytes)[_selectedScanIndex];
    _timePlotView.showsSelection = YES;
    [_timePlotView setNeedsDisplay:YES];
}

- (double)timeValueForScanIndex:(NSUInteger)scanIndex
{
    if (_timeAxisControl.selectedSegment == HDCVTimeAxisModeExperiment) {
        return [_loadedFile experimentTimeSecondsAtScan:scanIndex];
    }
    return [_loadedFile sequenceTimeSecondsAtScan:scanIndex];
}

- (void)scanSliderChanged:(id)sender
{
    (void)sender;
    if (_loadedFile == nil) {
        return;
    }
    _selectedScanIndex = (NSUInteger)llround(_scanSlider.doubleValue);
    _scanSlider.doubleValue = (double)_selectedScanIndex;
    [self refreshCurrentScan];
}

- (void)pointSliderChanged:(id)sender
{
    (void)sender;
    if (_loadedFile == nil) {
        return;
    }
    _selectedPointIndex = (NSUInteger)llround(_pointSlider.doubleValue);
    _pointSlider.doubleValue = (double)_selectedPointIndex;
    [self refreshCurrentScan];
    [self requestPointTraceRefresh];
}

- (void)timeAxisModeChanged:(id)sender
{
    (void)sender;
    if (_loadedFile == nil) {
        return;
    }
    [self refreshHeatmapTicks];
    [self refreshTimePlot];
    [self refreshCurrentScan];
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
    [self refreshCurrentScan];
    [self requestPointTraceRefresh];
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
        const float *trace = _currentTraceData.bytes;
        return trace[index];
    }
    if (view == _cvPlotView) {
        const float *scan = _currentScanData.bytes;
        return scan[index];
    }
    return 0.0;
}

@end

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        HDCVViewerController *controller = [[HDCVViewerController alloc] init];
        NSMutableArray<NSString *> *arguments = [NSMutableArray array];
        for (int i = 0; i < argc; ++i) {
            [arguments addObject:[NSString stringWithUTF8String:argv[i]]];
        }
        [controller setInitialPathFromArguments:arguments];
        app.delegate = controller;
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        [app run];
    }
    return 0;
}
