#import <AppKit/AppKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#include "hdcv_analysis.h"

#include <ctype.h>
#include <errno.h>
#include <float.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

typedef NS_ENUM(NSInteger, HDCVLinePlotInteractionMode) {
    HDCVLinePlotInteractionModeNone = 0,
    HDCVLinePlotInteractionModeSelectX = 1,
};

typedef NS_ENUM(NSInteger, HDCVHeatmapDragTarget) {
    HDCVHeatmapDragTargetNone = 0,
    HDCVHeatmapDragTargetSelectionX = 1,
    HDCVHeatmapDragTargetSelectionY = 2,
    HDCVHeatmapDragTargetSelectionXY = 3,
    HDCVHeatmapDragTargetBackgroundX = 4,
};

typedef NS_ENUM(NSInteger, HDCVLinePlotDragTarget) {
    HDCVLinePlotDragTargetNone = 0,
    HDCVLinePlotDragTargetSelectedX = 1,
    HDCVLinePlotDragTargetBackgroundX = 2,
};

typedef NS_ENUM(NSInteger, HDCVAxisEditTarget) {
    HDCVAxisEditTargetNone = 0,
    HDCVAxisEditTargetXMin = 1,
    HDCVAxisEditTargetXMax = 2,
    HDCVAxisEditTargetYMin = 3,
    HDCVAxisEditTargetYMax = 4,
    HDCVAxisEditTargetColorMin = 5,
    HDCVAxisEditTargetColorMax = 6,
};

typedef NS_OPTIONS(NSUInteger, HDCVExportOptions) {
    HDCVExportOptionColorPlot = 1U << 0U,
    HDCVExportOptionTimePlot = 1U << 1U,
    HDCVExportOptionCVPlot = 1U << 2U,
    HDCVExportOptionBackgroundCVPlot = 1U << 3U,
};

static const NSUInteger HDCVCVSelectedHalfWindow = 1U;
static const NSUInteger HDCVWaveformProgramVoltageRows = 10U;
static const NSUInteger HDCVWaveformProgramIntervalRows = 9U;
static NSString *const HDCVExportOptionsDefaultsKey = @"HDCVExportOptions";

@class HDCVDropHostView;
@class HDCVHeatmapView;
@class HDCVLinePlotView;
@class HDCVWaveformProgramView;
@class HDCVSwitchControl;

@protocol HDCVDropHostViewDelegate <NSObject>
- (void)dropHostView:(HDCVDropHostView *)view didReceiveFilePath:(NSString *)filePath;
@end

@protocol HDCVHeatmapViewDelegate <NSObject>
- (void)heatmapView:(HDCVHeatmapView *)view didDragSelectionScanIndex:(NSUInteger)scanIndex pointIndex:(NSUInteger)pointIndex updateScan:(BOOL)updateScan updatePoint:(BOOL)updatePoint;
- (void)heatmapView:(HDCVHeatmapView *)view didDragBackgroundScanIndex:(NSUInteger)scanIndex;
- (void)heatmapView:(HDCVHeatmapView *)view didEditAxisTarget:(HDCVAxisEditTarget)target value:(double)value;
@end

@protocol HDCVLinePlotDataSource <NSObject>
- (NSUInteger)sampleCountForLinePlotView:(HDCVLinePlotView *)view;
- (double)linePlotView:(HDCVLinePlotView *)view xValueAtIndex:(NSUInteger)index;
- (double)linePlotView:(HDCVLinePlotView *)view yValueAtIndex:(NSUInteger)index;
@end

@protocol HDCVLinePlotViewDelegate <NSObject>
- (void)linePlotView:(HDCVLinePlotView *)view didDragXValue:(double)xValue yValue:(double)yValue target:(HDCVLinePlotDragTarget)target;
- (void)linePlotView:(HDCVLinePlotView *)view didEditAxisTarget:(HDCVAxisEditTarget)target value:(double)value;
- (void)linePlotView:(HDCVLinePlotView *)view didNavigateToXMin:(double)xMin xMax:(double)xMax yMin:(double)yMin yMax:(double)yMax;
- (void)linePlotViewDidRequestResetView:(HDCVLinePlotView *)view;
@end

@interface HDCVDropHostView : NSView <NSDraggingDestination>
@property(nonatomic, weak) id<HDCVDropHostViewDelegate> delegate;
@property(nonatomic) BOOL dragHighlight;
@end

@interface HDCVSwitchControl : NSControl
@property(nonatomic) BOOL on;
@end

@interface HDCVHeatmapView : NSView <NSTextFieldDelegate>
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
@property(nonatomic) NSUInteger visibleScanMinIndex;
@property(nonatomic) NSUInteger visibleScanMaxIndex;
@property(nonatomic) NSUInteger visiblePointMinIndex;
@property(nonatomic) NSUInteger visiblePointMaxIndex;
@property(nonatomic, copy) NSString *titleText;
@property(nonatomic, copy) NSString *subtitleText;
@property(nonatomic) double colorScaleMinNA;
@property(nonatomic) double colorScaleMaxNA;
@end

@interface HDCVLinePlotView : NSView <NSTextFieldDelegate>
@property(nonatomic, weak) id<HDCVLinePlotDataSource> dataSource;
@property(nonatomic, weak) id<HDCVLinePlotViewDelegate> delegate;
@property(nonatomic) HDCVLinePlotInteractionMode interactionMode;
@property(nonatomic) BOOL viewNavigationEnabled;
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
@property(nonatomic) double backgroundXValue;
@property(nonatomic) BOOL showsSelection;
@property(nonatomic) BOOL showsBaseline;
@property(nonatomic) BOOL showsBackgroundX;
@end

@interface HDCVWaveformProgramView : NSView
@property(nonatomic, copy) NSArray<NSDictionary<NSString *, NSString *> *> *rows;
@property(nonatomic, copy) NSString *summaryText;
- (CGFloat)preferredContentHeight;
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
- (uint32_t)phasePeriod;
- (uint32_t)runCount;
- (uint32_t)scansPerRun;
- (BOOL)hasExperimentTiming;
- (double)runDurationSeconds;
- (double)delayBetweenRunsSeconds;
- (float)voltageAtPoint:(NSUInteger)pointIndex;
- (double)withinScanTimeSecondsAtPoint:(NSUInteger)pointIndex;
- (double)sequenceTimeSecondsAtScan:(NSUInteger)scanIndex;
- (double)experimentTimeSecondsAtScan:(NSUInteger)scanIndex;
- (uint32_t)waveformPointCount;
- (uint32_t)waveformFullPointCount;
- (double)waveformCycleDurationSeconds;
- (double)waveformFullDurationSeconds;
- (NSData *)voltageData;
- (NSData *)waveformData;
- (NSData *)overviewData;
- (BOOL)copyScanAtIndex:(uint32_t)scanIndex intoMutableData:(NSMutableData *)buffer min:(float *)outMin max:(float *)outMax;
- (BOOL)copyPointTraceAtIndex:(uint32_t)pointIndex intoMutableData:(NSMutableData *)buffer min:(float *)outMin max:(float *)outMax;
@end

@interface HDCVViewerController : NSObject <NSApplicationDelegate, NSTextFieldDelegate, HDCVDropHostViewDelegate, HDCVHeatmapViewDelegate, HDCVLinePlotDataSource, HDCVLinePlotViewDelegate>
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

static void HDCVHeatmapRGBForNormalized(float normalized, float *outR, float *outG, float *outB)
{
    float t = (MAX(-1.0f, MIN(1.0f, normalized)) + 1.0f) * 0.5f;
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

    *outR = r;
    *outG = g;
    *outB = b;
}

static BOOL HDCVFiniteRange(const float *values, size_t count, float *outMin, float *outMax)
{
    BOOL found = NO;
    float minValue = 0.0f;
    float maxValue = 0.0f;

    for (size_t i = 0U; i < count; ++i) {
        float value = values[i];
        if (!isfinite(value)) {
            continue;
        }
        if (!found || value < minValue) {
            minValue = value;
        }
        if (!found || value > maxValue) {
            maxValue = value;
        }
        found = YES;
    }

    if (!found) {
        return NO;
    }
    if (outMin != NULL) {
        *outMin = minValue;
    }
    if (outMax != NULL) {
        *outMax = maxValue;
    }
    return YES;
}

static void HDCVNormalizeDivergingColorLimits(double *minValue, double *maxValue)
{
    double positive = MAX(isfinite(*maxValue) ? *maxValue : 0.0, 0.0);
    double negative = MIN(isfinite(*minValue) ? *minValue : 0.0, 0.0);
    double fallback = MAX(MAX(fabs(positive), fabs(negative)), 1.0);

    if (positive <= 1.0e-12) {
        positive = fallback;
    }
    if (negative >= -1.0e-12) {
        negative = -fallback;
    }

    *minValue = negative;
    *maxValue = positive;
}

static float HDCVNormalizeCurrentForColor(float value, double minValue, double maxValue)
{
    double denominator = (value >= 0.0f) ? maxValue : -minValue;
    if (!isfinite(value)) {
        return 0.0f;
    }
    if (denominator <= 1.0e-12) {
        denominator = 1.0;
    }
    return (float)MAX(-1.0, MIN(1.0, (double)value / denominator));
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

static BOOL HDCVParseLeadingDouble(NSString *string, double *outValue)
{
    const char *text = string.UTF8String;
    char *endptr = NULL;
    double parsed;

    if (text == NULL) {
        return NO;
    }
    parsed = strtod(text, &endptr);
    if (endptr == text || !isfinite(parsed)) {
        return NO;
    }
    if (outValue != NULL) {
        *outValue = parsed;
    }
    return YES;
}

static NSUInteger HDCVPhaseAlignedBackgroundIndex(
    NSUInteger rawBackgroundIndex,
    NSUInteger scanIndex,
    NSUInteger scanCount,
    NSUInteger phasePeriod
)
{
    NSUInteger period = MAX(phasePeriod, 1U);
    NSUInteger rawIndex;
    NSUInteger targetMod;
    double nearestPeriod;
    NSInteger nearest;
    NSInteger maxScan;

    if (scanCount == 0U) {
        return 0U;
    }

    rawIndex = MIN(rawBackgroundIndex, scanCount - 1U);
    if (period <= 1U) {
        return rawIndex;
    }

    targetMod = scanIndex % period;
    nearestPeriod = round(((double)rawIndex - (double)targetMod) / (double)period);
    nearest = (NSInteger)targetMod + (NSInteger)llround(nearestPeriod) * (NSInteger)period;
    maxScan = (NSInteger)scanCount - 1;
    nearest = MAX(0, MIN(maxScan, nearest));

    while ((NSUInteger)nearest > scanIndex && nearest - (NSInteger)period >= 0) {
        nearest -= (NSInteger)period;
    }
    return (NSUInteger)MAX(0, MIN(maxScan, nearest));
}

static BOOL HDCVScanIndexMatchesPhase(NSUInteger scanIndex, NSUInteger phaseIndex, NSUInteger phasePeriod)
{
    NSUInteger period = MAX(phasePeriod, 1U);
    return period <= 1U || (scanIndex % period) == (phaseIndex % period);
}

static NSUInteger HDCVNearestScanIndexForPhase(
    NSUInteger scanIndex,
    NSUInteger scanCount,
    NSUInteger phaseIndex,
    NSUInteger phasePeriod
)
{
    NSUInteger period = MAX(phasePeriod, 1U);
    NSUInteger targetPhase = phaseIndex % period;
    NSInteger candidate;
    NSInteger maxScan;

    if (scanCount == 0U) {
        return 0U;
    }
    if (period <= 1U || scanCount <= 1U) {
        return MIN(scanIndex, scanCount - 1U);
    }
    if (targetPhase >= scanCount) {
        targetPhase = 0U;
    }

    candidate = (NSInteger)targetPhase + (NSInteger)llround(((double)scanIndex - (double)targetPhase) / (double)period) * (NSInteger)period;
    maxScan = (NSInteger)scanCount - 1;
    while (candidate < 0) {
        candidate += (NSInteger)period;
    }
    while (candidate > maxScan) {
        candidate -= (NSInteger)period;
    }
    return (NSUInteger)MAX(0, MIN(maxScan, candidate));
}

static NSUInteger HDCVScanIndexForPhaseSample(
    NSUInteger sampleIndex,
    NSUInteger scanCount,
    NSUInteger phaseIndex,
    NSUInteger phasePeriod
)
{
    NSUInteger period = MAX(phasePeriod, 1U);
    NSUInteger scanIndex;

    if (scanCount == 0U) {
        return 0U;
    }
    if (period <= 1U) {
        return MIN(sampleIndex, scanCount - 1U);
    }
    scanIndex = (phaseIndex % period) + (sampleIndex * period);
    return MIN(scanIndex, scanCount - 1U);
}

static NSUInteger HDCVPhaseSampleCount(NSUInteger scanCount, NSUInteger phaseIndex, NSUInteger phasePeriod)
{
    NSUInteger period = MAX(phasePeriod, 1U);
    NSUInteger firstScan = phaseIndex % period;

    if (scanCount == 0U) {
        return 0U;
    }
    if (period <= 1U) {
        return scanCount;
    }
    if (firstScan >= scanCount) {
        return 0U;
    }
    return ((scanCount - 1U - firstScan) / period) + 1U;
}

static NSUInteger HDCVFirstPhaseScanInRange(
    NSUInteger minScan,
    NSUInteger maxScan,
    NSUInteger phaseIndex,
    NSUInteger phasePeriod
)
{
    NSUInteger period = MAX(phasePeriod, 1U);
    NSUInteger targetPhase = phaseIndex % period;
    NSUInteger remainder;
    NSUInteger delta;

    if (maxScan < minScan) {
        return NSNotFound;
    }
    if (period <= 1U) {
        return minScan;
    }
    remainder = minScan % period;
    delta = (targetPhase + period - remainder) % period;
    if (minScan + delta > maxScan) {
        return NSNotFound;
    }
    return minScan + delta;
}

static NSUInteger HDCVPhaseSampleCountInRange(
    NSUInteger minScan,
    NSUInteger maxScan,
    NSUInteger phaseIndex,
    NSUInteger phasePeriod
)
{
    NSUInteger period = MAX(phasePeriod, 1U);
    NSUInteger firstScan = HDCVFirstPhaseScanInRange(minScan, maxScan, phaseIndex, period);

    if (firstScan == NSNotFound) {
        return 0U;
    }
    if (period <= 1U) {
        return maxScan - firstScan + 1U;
    }
    return ((maxScan - firstScan) / period) + 1U;
}

static float HDCVAverageTraceInPhaseWindow(
    const float *trace,
    NSUInteger scanCount,
    NSUInteger centerScan,
    NSUInteger phaseIndex,
    NSUInteger phasePeriod,
    NSUInteger halfWindow
)
{
    NSUInteger period = MAX(phasePeriod, 1U);
    NSUInteger center = HDCVNearestScanIndexForPhase(centerScan, scanCount, phaseIndex, period);
    NSInteger start = (NSInteger)center - ((NSInteger)halfWindow * (NSInteger)period);
    NSInteger end = (NSInteger)center + ((NSInteger)halfWindow * (NSInteger)period);
    double sum = 0.0;
    NSUInteger count = 0U;

    if (scanCount == 0U) {
        return 0.0f;
    }

    while (start < 0) {
        start += (NSInteger)period;
    }
    while (end >= (NSInteger)scanCount) {
        end -= (NSInteger)period;
    }

    for (NSInteger scanIndex = start; scanIndex <= end; scanIndex += (NSInteger)period) {
        if (scanIndex >= 0 && scanIndex < (NSInteger)scanCount) {
            sum += (double)trace[scanIndex];
            count += 1U;
        }
    }

    if (count == 0U) {
        return trace[center];
    }
    return (float)(sum / (double)count);
}

static void HDCVApplyPhaseAlignedBackgroundToTrace(
    const float *source,
    float *destination,
    NSUInteger scanCount,
    NSUInteger rawBackgroundIndex,
    NSUInteger phasePeriod
)
{
    for (NSUInteger scanIndex = 0U; scanIndex < scanCount; ++scanIndex) {
        NSUInteger alignedIndex = HDCVPhaseAlignedBackgroundIndex(rawBackgroundIndex, scanIndex, scanCount, phasePeriod);
        destination[scanIndex] = source[scanIndex] - source[alignedIndex];
    }
}

static void HDCVSetCSVError(NSError **error, NSURL *url, NSString *message)
{
    if (error == NULL) {
        return;
    }
    *error = [NSError errorWithDomain:HDCVViewerErrorDomain
                                 code:11
                             userInfo:@{
                                 NSLocalizedDescriptionKey: message,
                                 NSURLErrorKey: url
                             }];
}

static FILE *HDCVOpenCSVFile(NSURL *url, NSError **error)
{
    FILE *file = fopen(url.path.fileSystemRepresentation, "w");
    if (file == NULL) {
        NSString *message = [NSString stringWithFormat:@"Could not create %@: %s", url.lastPathComponent, strerror(errno)];
        HDCVSetCSVError(error, url, message);
        return NULL;
    }
    (void)setvbuf(file, NULL, _IOFBF, 1024U * 1024U);
    return file;
}

static BOOL HDCVCloseCSVFile(FILE *file, NSURL *url, NSError **error)
{
    int hadWriteError = ferror(file);
    int closeResult = fclose(file);
    if (hadWriteError != 0 || closeResult != 0) {
        NSString *message = [NSString stringWithFormat:@"Could not finish writing %@: %s", url.lastPathComponent, strerror(errno)];
        HDCVSetCSVError(error, url, message);
        return NO;
    }
    return YES;
}

static NSURL *HDCVExportURLForSuffix(NSURL *baseURL, NSString *suffix, BOOL singleFile)
{
    if (singleFile) {
        return baseURL;
    }

    NSURL *directoryURL = [baseURL URLByDeletingLastPathComponent];
    NSString *baseName = baseURL.lastPathComponent.stringByDeletingPathExtension;
    if (baseName.length == 0U) {
        baseName = @"hdcv_export";
    }
    return [directoryURL URLByAppendingPathComponent:[NSString stringWithFormat:@"%@_%@.csv", baseName, suffix]];
}

typedef struct {
    double b0;
    double b1;
    double b2;
    double a1;
    double a2;
} HDCVBiquad;

static HDCVBiquad HDCVButterworthLowpass(double cutoffHz, double sampleRateHz)
{
    double k = tan(M_PI * cutoffHz / sampleRateHz);
    double norm = 1.0 / (1.0 + (M_SQRT2 * k) + (k * k));
    HDCVBiquad c;
    c.b0 = k * k * norm;
    c.b1 = 2.0 * c.b0;
    c.b2 = c.b0;
    c.a1 = 2.0 * ((k * k) - 1.0) * norm;
    c.a2 = (1.0 - (M_SQRT2 * k) + (k * k)) * norm;
    return c;
}

static HDCVBiquad HDCVButterworthHighpass(double cutoffHz, double sampleRateHz)
{
    double k = tan(M_PI * cutoffHz / sampleRateHz);
    double norm = 1.0 / (1.0 + (M_SQRT2 * k) + (k * k));
    HDCVBiquad c;
    c.b0 = norm;
    c.b1 = -2.0 * c.b0;
    c.b2 = c.b0;
    c.a1 = 2.0 * ((k * k) - 1.0) * norm;
    c.a2 = (1.0 - (M_SQRT2 * k) + (k * k)) * norm;
    return c;
}

static void HDCVApplyBiquadForward(const float *src, float *dst, size_t count, HDCVBiquad c)
{
    double x1 = 0.0;
    double x2 = 0.0;
    double y1 = 0.0;
    double y2 = 0.0;

    for (size_t i = 0U; i < count; ++i) {
        double x0 = (double)src[i];
        double y0 = (c.b0 * x0) + (c.b1 * x1) + (c.b2 * x2) - (c.a1 * y1) - (c.a2 * y2);
        dst[i] = (float)y0;
        x2 = x1;
        x1 = x0;
        y2 = y1;
        y1 = y0;
    }
}

static void HDCVReverseFloatArray(float *values, size_t count)
{
    for (size_t i = 0U; i < count / 2U; ++i) {
        float tmp = values[i];
        values[i] = values[count - 1U - i];
        values[count - 1U - i] = tmp;
    }
}

static void HDCVApplyBiquadZeroPhase(float *values, float *scratch, size_t count, HDCVBiquad c)
{
    HDCVApplyBiquadForward(values, scratch, count, c);
    HDCVReverseFloatArray(scratch, count);
    HDCVApplyBiquadForward(scratch, values, count, c);
    HDCVReverseFloatArray(values, count);
}

static BOOL HDCVApplyButterworthBandpass(float *values, size_t count, double sampleRateHz)
{
    double nyquist = sampleRateHz * 0.5;
    double lowHz = 0.01;
    double highHz = MIN(2.0, nyquist * 0.80);
    float *scratch;

    if (count < 8U || sampleRateHz <= 0.0 || highHz <= lowHz) {
        return NO;
    }

    scratch = (float *)malloc(count * sizeof(*scratch));
    if (scratch == NULL) {
        return NO;
    }

    HDCVApplyBiquadZeroPhase(values, scratch, count, HDCVButterworthHighpass(lowHz, sampleRateHz));
    HDCVApplyBiquadZeroPhase(values, scratch, count, HDCVButterworthLowpass(highHz, sampleRateHz));
    free(scratch);
    return YES;
}

static int HDCVCompareFloat(const void *a, const void *b)
{
    float fa = *(const float *)a;
    float fb = *(const float *)b;
    return (fa > fb) - (fa < fb);
}

static int HDCVVoltageStepDirection(float previous, float current, float epsilon)
{
    float delta = current - previous;
    if (delta > epsilon) {
        return 1;
    }
    if (delta < -epsilon) {
        return -1;
    }
    return 0;
}

static void HDCVExpandRangeToIncludeZero(double *minValue, double *maxValue)
{
    if (minValue == NULL || maxValue == NULL) {
        return;
    }
    if (*minValue > 0.0) {
        *minValue = 0.0;
    }
    if (*maxValue < 0.0) {
        *maxValue = 0.0;
    }
}

static void HDCVAddUniqueDoubleTick(NSMutableArray<NSNumber *> *ticks, double value, double epsilon)
{
    for (NSNumber *tick in ticks) {
        if (fabs(tick.doubleValue - value) <= epsilon) {
            return;
        }
    }
    [ticks addObject:@(value)];
}

static NSInteger HDCVCompareNSNumberDouble(id a, id b, void *context)
{
    (void)context;
    double first = [a doubleValue];
    double second = [b doubleValue];
    if (first < second) {
        return NSOrderedAscending;
    }
    if (first > second) {
        return NSOrderedDescending;
    }
    return NSOrderedSame;
}

static NSArray<NSNumber *> *HDCVAxisTickValues(double minValue, double maxValue, NSUInteger baseTickCount, BOOL includeZero)
{
    NSMutableArray<NSNumber *> *ticks = [NSMutableArray array];
    double range = maxValue - minValue;
    double epsilon = MAX(fabs(range) * 1.0e-9, 1.0e-9);

    if (baseTickCount == 0U || range <= 0.0 || !isfinite(range)) {
        return @[];
    }

    if (baseTickCount == 1U) {
        HDCVAddUniqueDoubleTick(ticks, minValue, epsilon);
    } else {
        for (NSUInteger tick = 0U; tick < baseTickCount; ++tick) {
            double fraction = (double)tick / (double)(baseTickCount - 1U);
            HDCVAddUniqueDoubleTick(ticks, minValue + (range * fraction), epsilon);
        }
    }

    if (includeZero && minValue <= 0.0 && maxValue >= 0.0) {
        NSUInteger nearestInteriorIndex = NSNotFound;
        double nearestInteriorDistance = DBL_MAX;
        for (NSUInteger index = 0U; index < ticks.count; ++index) {
            double tickValue = ticks[index].doubleValue;
            if (fabs(tickValue) <= epsilon) {
                return [ticks sortedArrayUsingFunction:HDCVCompareNSNumberDouble context:NULL];
            }
            if (index > 0U && index + 1U < ticks.count && fabs(tickValue) < nearestInteriorDistance) {
                nearestInteriorDistance = fabs(tickValue);
                nearestInteriorIndex = index;
            }
        }
        if (nearestInteriorIndex != NSNotFound && nearestInteriorDistance <= range * 0.12) {
            ticks[nearestInteriorIndex] = @0.0;
        } else {
            HDCVAddUniqueDoubleTick(ticks, 0.0, epsilon);
        }
    }

    return [ticks sortedArrayUsingFunction:HDCVCompareNSNumberDouble context:NULL];
}

static float HDCVWaveformProgramVoltageAtIndex(const float *voltage, NSUInteger count, NSUInteger index)
{
    if (voltage == NULL || count == 0U) {
        return 0.0f;
    }
    return (index < count) ? voltage[index] : voltage[0];
}

static NSString *HDCVFormatWaveformVoltage(double value)
{
    return [NSString stringWithFormat:@"%.3f", value];
}

static NSString *HDCVFormatWaveformDuration(double milliseconds)
{
    if (milliseconds <= 0.0005) {
        return @"0";
    }
    if (milliseconds < 0.01) {
        return [NSString stringWithFormat:@"%.4f", milliseconds];
    }
    return [NSString stringWithFormat:@"%.3f", milliseconds];
}

static NSString *HDCVFormatWaveformRate(double voltsPerSecond, BOOL isStep)
{
    double magnitude = fabs(voltsPerSecond);

    if (isStep) {
        return @"step";
    }
    if (magnitude >= 100.0) {
        return [NSString stringWithFormat:@"%.0f", voltsPerSecond];
    }
    if (magnitude >= 10.0) {
        return [NSString stringWithFormat:@"%.1f", voltsPerSecond];
    }
    return [NSString stringWithFormat:@"%.2f", voltsPerSecond];
}

static double HDCVWaveformFullDisplayDurationMs(NSUInteger activePointCount, NSUInteger fullPointCount, double sampleRateHz)
{
    if (fullPointCount > 0U && sampleRateHz > 0.0) {
        return ((double)fullPointCount * 1000.0) / sampleRateHz;
    }
    if (activePointCount > 1U && sampleRateHz > 0.0) {
        return ((double)(activePointCount - 1U) * 1000.0) / sampleRateHz;
    }
    return 0.0;
}

static NSUInteger HDCVWaveformDisplayPointCount(NSUInteger activePointCount, NSUInteger fullPointCount, double sampleRateHz)
{
    NSUInteger displayPointCount;
    double displayDurationMs;

    if (activePointCount == 0U || sampleRateHz <= 0.0) {
        return activePointCount;
    }

    displayDurationMs = HDCVWaveformFullDisplayDurationMs(activePointCount, fullPointCount, sampleRateHz);
    if (displayDurationMs <= 0.0) {
        return activePointCount;
    }

    displayPointCount = (NSUInteger)llround((displayDurationMs / 1000.0) * sampleRateHz) + 1U;
    return MAX(activePointCount, displayPointCount);
}

static NSArray<NSDictionary<NSString *, NSString *> *> *HDCVBuildWaveformProgramRows(
    const float *voltage,
    NSUInteger count,
    double sampleRateHz,
    double displayDurationMs,
    NSString **outSummary
)
{
    NSMutableArray<NSDictionary<NSString *, NSNumber *> *> *rawSegments = [NSMutableArray array];
    NSMutableArray<NSDictionary<NSString *, NSNumber *> *> *intervals = [NSMutableArray array];
    NSMutableArray<NSDictionary<NSString *, NSString *> *> *rows = [NSMutableArray array];
    float voltageMin;
    float voltageMax;
    float epsilon;
    double sampleIntervalMs;
    double minimumHoldMs;
    double maxAbsRate = 0.0;
    double programmedDurationMs = 0.0;
    NSUInteger parseCount;
    NSUInteger segmentStart;
    NSUInteger currentIntervalStart;
    int segmentDirection;
    BOOL hasSegment = NO;

    if (outSummary != NULL) {
        *outSummary = @"No waveform loaded";
    }
    if (voltage == NULL || count == 0U || sampleRateHz <= 0.0) {
        return @[];
    }

    voltageMin = voltage[0];
    voltageMax = voltage[0];
    for (NSUInteger index = 1U; index < count; ++index) {
        voltageMin = MIN(voltageMin, voltage[index]);
        voltageMax = MAX(voltageMax, voltage[index]);
    }
    epsilon = MAX(1.0e-6f, (voltageMax - voltageMin) * 1.0e-5f);
    sampleIntervalMs = 1000.0 / sampleRateHz;
    minimumHoldMs = MAX(sampleIntervalMs * 1.5, 0.05);
    parseCount = count;
    if (displayDurationMs > ((double)count * sampleIntervalMs) + (sampleIntervalMs * 0.5)) {
        parseCount += 1U;
    }

    segmentStart = 0U;
    segmentDirection = 0;
    for (NSUInteger index = 1U; index < parseCount; ++index) {
        float previous = HDCVWaveformProgramVoltageAtIndex(voltage, count, index - 1U);
        float current = HDCVWaveformProgramVoltageAtIndex(voltage, count, index);
        int direction = HDCVVoltageStepDirection(previous, current, epsilon);
        if (!hasSegment) {
            segmentDirection = direction;
            hasSegment = YES;
            continue;
        }

        if (direction != segmentDirection) {
            [rawSegments addObject:@{
                @"start": @(segmentStart),
                @"end": @(index - 1U),
                @"direction": @(segmentDirection)
            }];
            segmentStart = index - 1U;
            segmentDirection = direction;
        }
    }

    if (hasSegment) {
        [rawSegments addObject:@{
            @"start": @(segmentStart),
            @"end": @(parseCount - 1U),
            @"direction": @(segmentDirection)
        }];
    }

    currentIntervalStart = 0U;
    for (NSDictionary<NSString *, NSNumber *> *segment in rawSegments) {
        NSUInteger segmentEnd = segment[@"end"].unsignedIntegerValue;
        int direction = segment[@"direction"].intValue;
        double durationMs = ((double)(segmentEnd - currentIntervalStart) * 1000.0) / sampleRateHz;
        float startVoltage;
        float endVoltage;

        if (segmentEnd <= currentIntervalStart) {
            continue;
        }
        if (direction == 0 && durationMs < minimumHoldMs) {
            currentIntervalStart = segmentEnd;
            continue;
        }

        startVoltage = HDCVWaveformProgramVoltageAtIndex(voltage, count, currentIntervalStart);
        endVoltage = HDCVWaveformProgramVoltageAtIndex(voltage, count, segmentEnd);
        [intervals addObject:@{
            @"start": @(currentIntervalStart),
            @"end": @(segmentEnd),
            @"direction": @(HDCVVoltageStepDirection(startVoltage, endVoltage, epsilon))
        }];
        programmedDurationMs += durationMs;
        currentIntervalStart = segmentEnd;
    }

    for (NSDictionary<NSString *, NSNumber *> *interval in intervals) {
        NSUInteger startIndex = interval[@"start"].unsignedIntegerValue;
        NSUInteger endIndex = interval[@"end"].unsignedIntegerValue;
        double durationMs = ((double)(endIndex - startIndex) * 1000.0) / sampleRateHz;
        double deltaV = (double)HDCVWaveformProgramVoltageAtIndex(voltage, count, endIndex)
            - (double)HDCVWaveformProgramVoltageAtIndex(voltage, count, startIndex);
        BOOL isStep = durationMs <= sampleIntervalMs * 1.5 && fabs(deltaV) > (double)epsilon;
        double rate = isStep ? 0.0 : deltaV / (durationMs / 1000.0);
        if (!isStep) {
            maxAbsRate = MAX(maxAbsRate, fabs(rate));
        }
    }

    for (NSUInteger rowIndex = 0U; rowIndex < HDCVWaveformProgramVoltageRows; ++rowIndex) {
        BOOL intervalRow = rowIndex < intervals.count && rowIndex < HDCVWaveformProgramIntervalRows;
        BOOL endpointRow = rowIndex == intervals.count && intervals.count < HDCVWaveformProgramVoltageRows;
        BOOL rowActive = intervalRow || endpointRow;
        NSUInteger pointIndex = 0U;
        NSString *voltageText = @"--";
        NSString *timeText = @"";
        NSString *rateText = @"";

        if (intervalRow) {
            NSDictionary<NSString *, NSNumber *> *interval = intervals[rowIndex];
            NSUInteger startIndex = interval[@"start"].unsignedIntegerValue;
            NSUInteger endIndex = interval[@"end"].unsignedIntegerValue;
            double durationMs = ((double)(endIndex - startIndex) * 1000.0) / sampleRateHz;
            double deltaV = (double)HDCVWaveformProgramVoltageAtIndex(voltage, count, endIndex)
                - (double)HDCVWaveformProgramVoltageAtIndex(voltage, count, startIndex);
            BOOL isStep = durationMs <= sampleIntervalMs * 1.5 && fabs(deltaV) > (double)epsilon;
            double rate = isStep ? 0.0 : deltaV / (durationMs / 1000.0);

            if (isStep) {
                durationMs = 0.0;
            }
            pointIndex = startIndex;
            voltageText = HDCVFormatWaveformVoltage((double)HDCVWaveformProgramVoltageAtIndex(voltage, count, pointIndex));
            timeText = HDCVFormatWaveformDuration(durationMs);
            rateText = HDCVFormatWaveformRate(rate, isStep);
        } else if (endpointRow) {
            if (intervals.count > 0U) {
                pointIndex = intervals.lastObject[@"end"].unsignedIntegerValue;
            }
            voltageText = HDCVFormatWaveformVoltage((double)HDCVWaveformProgramVoltageAtIndex(voltage, count, pointIndex));
        } else if (!rowActive && rowIndex < HDCVWaveformProgramIntervalRows) {
            timeText = @"--";
            rateText = @"--";
        }

        [rows addObject:@{
            @"active": rowActive ? @"1" : @"0",
            @"time": timeText,
            @"rate": rateText,
            @"voltage": voltageText
        }];
    }

    if (outSummary != NULL) {
        NSUInteger activeIntervalCount = MIN(intervals.count, HDCVWaveformProgramIntervalRows);
        NSUInteger activeVoltageCount = MIN(intervals.count + 1U, HDCVWaveformProgramVoltageRows);
        double holdMs = MAX(0.0, displayDurationMs - programmedDurationMs);
        if (intervals.count > HDCVWaveformProgramIntervalRows) {
            *outSummary = [NSString stringWithFormat:@"%lu active times, showing first %lu",
                           (unsigned long)intervals.count,
                           (unsigned long)HDCVWaveformProgramIntervalRows];
        } else if (holdMs > sampleIntervalMs) {
            *outSummary = [NSString stringWithFormat:@"%lu active voltages / %lu times / %@ ms hold",
                           (unsigned long)activeVoltageCount,
                           (unsigned long)activeIntervalCount,
                           HDCVFormatWaveformDuration(holdMs)];
        } else if (maxAbsRate > 0.0) {
            *outSummary = [NSString stringWithFormat:@"%lu active voltages / %lu times / max %.0f V/s",
                           (unsigned long)activeVoltageCount,
                           (unsigned long)activeIntervalCount,
                           maxAbsRate];
        } else {
            *outSummary = [NSString stringWithFormat:@"%lu active voltages / %lu times",
                           (unsigned long)activeVoltageCount,
                           (unsigned long)activeIntervalCount];
        }
    }

    return rows;
}

static void HDCVSmoothCVSegment(
    const float *source,
    float *destination,
    NSUInteger startIndex,
    NSUInteger endIndex,
    NSUInteger radius
)
{
    if (endIndex <= startIndex) {
        return;
    }

    for (NSUInteger index = startIndex; index < endIndex; ++index) {
        NSUInteger left = (index > startIndex + radius) ? index - radius : startIndex;
        NSUInteger right = MIN(endIndex - 1U, index + radius);
        double sum = 0.0;
        double weightSum = 0.0;

        for (NSUInteger neighbor = left; neighbor <= right; ++neighbor) {
            NSUInteger distance = (neighbor > index) ? neighbor - index : index - neighbor;
            double weight = (double)(radius + 1U - distance);
            sum += (double)source[neighbor] * weight;
            weightSum += weight;
        }

        destination[index] = (weightSum > 0.0) ? (float)(sum / weightSum) : source[index];
    }
}

static void HDCVApplyBackgroundSubtractedCVDenoise(float *values, const float *voltage, NSUInteger count)
{
    static const NSUInteger radius = 2U;
    float *source;
    float voltageMin;
    float voltageMax;
    float epsilon;
    NSUInteger segmentStart;
    int segmentDirection;

    if (values == NULL || voltage == NULL || count < ((radius * 2U) + 3U)) {
        return;
    }

    source = (float *)malloc((size_t)count * sizeof(*source));
    if (source == NULL) {
        return;
    }
    memcpy(source, values, (size_t)count * sizeof(*source));

    voltageMin = voltage[0];
    voltageMax = voltage[0];
    for (NSUInteger index = 1U; index < count; ++index) {
        voltageMin = MIN(voltageMin, voltage[index]);
        voltageMax = MAX(voltageMax, voltage[index]);
    }
    epsilon = MAX(1.0e-6f, (voltageMax - voltageMin) * 1.0e-5f);

    segmentStart = 0U;
    segmentDirection = 0;
    for (NSUInteger index = 1U; index < count; ++index) {
        int direction = HDCVVoltageStepDirection(voltage[index - 1U], voltage[index], epsilon);
        if (direction == 0) {
            continue;
        }
        if (segmentDirection != 0 && direction != segmentDirection && index > segmentStart + (radius * 2U)) {
            HDCVSmoothCVSegment(source, values, segmentStart, index, radius);
            segmentStart = index - 1U;
        }
        segmentDirection = direction;
    }
    HDCVSmoothCVSegment(source, values, segmentStart, count, radius);

    free(source);
}

static void HDCVRobustRange(const float *values, size_t count, float *outMin, float *outMax)
{
    size_t stride = MAX((size_t)1U, count / 65536U);
    size_t sampleCapacity = (count + stride - 1U) / stride;
    float *samples = (float *)malloc(sampleCapacity * sizeof(*samples));
    size_t sampleCount = 0U;
    float minValue = 0.0f;
    float maxValue = 0.0f;

    if (samples == NULL || count == 0U) {
        free(samples);
        if (outMin != NULL) {
            *outMin = 0.0f;
        }
        if (outMax != NULL) {
            *outMax = 1.0f;
        }
        return;
    }

    for (size_t i = 0U; i < count; i += stride) {
        float value = values[i];
        if (isfinite(value)) {
            samples[sampleCount++] = value;
        }
    }

    if (sampleCount == 0U) {
        free(samples);
        if (outMin != NULL) {
            *outMin = 0.0f;
        }
        if (outMax != NULL) {
            *outMax = 1.0f;
        }
        return;
    }

    qsort(samples, sampleCount, sizeof(*samples), HDCVCompareFloat);
    minValue = samples[(size_t)floor((double)(sampleCount - 1U) * 0.01)];
    maxValue = samples[(size_t)floor((double)(sampleCount - 1U) * 0.99)];
    if (maxValue <= minValue) {
        minValue = samples[0];
        maxValue = samples[sampleCount - 1U];
    }
    free(samples);

    if (outMin != NULL) {
        *outMin = minValue;
    }
    if (outMax != NULL) {
        *outMax = maxValue;
    }
}

static void HDCVRobustRangeForPhase(
    const float *values,
    size_t count,
    NSUInteger phaseIndex,
    NSUInteger phasePeriod,
    float *outMin,
    float *outMax
)
{
    NSUInteger period = MAX(phasePeriod, 1U);
    NSUInteger phase = phaseIndex % period;
    size_t phaseCount;
    float *samples;
    size_t sampleCount = 0U;
    float minValue;
    float maxValue;

    if (period <= 1U) {
        HDCVRobustRange(values, count, outMin, outMax);
        return;
    }

    phaseCount = HDCVPhaseSampleCount(count, phase, period);
    samples = (float *)malloc(MAX((size_t)1U, phaseCount) * sizeof(*samples));
    if (samples == NULL || phaseCount == 0U) {
        free(samples);
        if (outMin != NULL) {
            *outMin = 0.0f;
        }
        if (outMax != NULL) {
            *outMax = 1.0f;
        }
        return;
    }

    for (NSUInteger scanIndex = phase; scanIndex < count; scanIndex += period) {
        float value = values[scanIndex];
        if (isfinite(value)) {
            samples[sampleCount++] = value;
        }
    }

    if (sampleCount == 0U) {
        free(samples);
        if (outMin != NULL) {
            *outMin = 0.0f;
        }
        if (outMax != NULL) {
            *outMax = 1.0f;
        }
        return;
    }

    qsort(samples, sampleCount, sizeof(*samples), HDCVCompareFloat);
    minValue = samples[(size_t)floor((double)(sampleCount - 1U) * 0.01)];
    maxValue = samples[(size_t)floor((double)(sampleCount - 1U) * 0.99)];
    if (maxValue <= minValue) {
        minValue = samples[0];
        maxValue = samples[sampleCount - 1U];
    }
    free(samples);

    if (outMin != NULL) {
        *outMin = minValue;
    }
    if (outMax != NULL) {
        *outMax = maxValue;
    }
}

static BOOL HDCVApplyButterworthBandpassByPhase(float *values, size_t count, NSUInteger phasePeriod, double scanRateHz)
{
    NSUInteger period = MAX(phasePeriod, 1U);
    BOOL filtered = NO;

    if (period <= 1U) {
        return HDCVApplyButterworthBandpass(values, count, scanRateHz);
    }

    for (NSUInteger phase = 0U; phase < period; ++phase) {
        NSUInteger phaseCount = HDCVPhaseSampleCount(count, phase, period);
        NSMutableData *phaseData;
        float *phaseValues;
        NSUInteger j = 0U;

        if (phaseCount == 0U) {
            continue;
        }

        phaseData = [NSMutableData dataWithLength:phaseCount * sizeof(float)];
        phaseValues = phaseData.mutableBytes;
        for (NSUInteger scanIndex = phase; scanIndex < count; scanIndex += period) {
            phaseValues[j++] = values[scanIndex];
        }

        if (HDCVApplyButterworthBandpass(phaseValues, phaseCount, scanRateHz / (double)period)) {
            j = 0U;
            for (NSUInteger scanIndex = phase; scanIndex < count; scanIndex += period) {
                values[scanIndex] = phaseValues[j++];
            }
            filtered = YES;
        }
    }

    return filtered;
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

@implementation HDCVSwitchControl

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self != nil) {
        self.wantsLayer = YES;
        self.enabled = NO;
    }
    return self;
}

- (BOOL)isFlipped
{
    return YES;
}

- (NSSize)intrinsicContentSize
{
    return NSMakeSize(48.0, 28.0);
}

- (void)setOn:(BOOL)on
{
    _on = on;
    [self setNeedsDisplay:YES];
}

- (void)setEnabled:(BOOL)enabled
{
    [super setEnabled:enabled];
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect
{
    (void)dirtyRect;
    NSRect bounds = NSInsetRect(self.bounds, 2.0, 2.0);
    CGFloat knobDiameter = MAX(18.0, bounds.size.height - 4.0);
    CGFloat knobX = self.on ? (NSMaxX(bounds) - knobDiameter - 2.0) : (bounds.origin.x + 2.0);
    NSColor *trackColor = self.on ? HDCVAccentBlue() : [NSColor colorWithWhite:0.78 alpha:1.0];
    NSColor *knobColor = self.enabled ? NSColor.whiteColor : [NSColor colorWithWhite:0.92 alpha:1.0];

    if (!self.enabled) {
        trackColor = [trackColor colorWithAlphaComponent:0.45];
    }

    [trackColor setFill];
    NSBezierPath *track = [NSBezierPath bezierPathWithRoundedRect:bounds
                                                         xRadius:bounds.size.height * 0.5
                                                         yRadius:bounds.size.height * 0.5];
    [track fill];

    NSRect knobRect = NSMakeRect(knobX, bounds.origin.y + 2.0, knobDiameter, knobDiameter);
    [knobColor setFill];
    NSBezierPath *knob = [NSBezierPath bezierPathWithOvalInRect:knobRect];
    [knob fill];

    [[[NSColor blackColor] colorWithAlphaComponent:0.11] setStroke];
    knob.lineWidth = 0.5;
    [knob stroke];
}

- (void)mouseDown:(NSEvent *)event
{
    (void)event;
    if (!self.enabled) {
        return;
    }
    self.on = !self.on;
    [self sendAction:self.action to:self.target];
}

- (void)resetCursorRects
{
    if (self.enabled) {
        [self addCursorRect:self.bounds cursor:NSCursor.pointingHandCursor];
    }
}

@end

@implementation HDCVHeatmapView {
    HDCVHeatmapDragTarget _activeDragTarget;
    HDCVAxisEditTarget _activeAxisEditTarget;
    NSTextField *_axisEditor;
    NSTrackingArea *_trackingArea;
}

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self != nil) {
        _titleText = @"Color Plot";
        _subtitleText = @"No file loaded";
        _backgroundScanIndex = NSNotFound;
        _colorScaleMinNA = -1.0;
        _colorScaleMaxNA = 1.0;
        _visibleScanMinIndex = 0U;
        _visibleScanMaxIndex = NSNotFound;
        _visiblePointMinIndex = 0U;
        _visiblePointMaxIndex = NSNotFound;
        _activeDragTarget = HDCVHeatmapDragTargetNone;
        self.wantsLayer = YES;
        self.layer.backgroundColor = NSColor.whiteColor.CGColor;
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

- (NSRect)plotRect
{
    return NSMakeRect(66.0, 76.0, MAX(40.0, self.bounds.size.width - 138.0), MAX(40.0, self.bounds.size.height - 112.0));
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

- (void)setVisibleScanMinIndex:(NSUInteger)visibleScanMinIndex
{
    _visibleScanMinIndex = visibleScanMinIndex;
    [self setNeedsDisplay:YES];
}

- (void)setVisibleScanMaxIndex:(NSUInteger)visibleScanMaxIndex
{
    _visibleScanMaxIndex = visibleScanMaxIndex;
    [self setNeedsDisplay:YES];
}

- (void)setVisiblePointMinIndex:(NSUInteger)visiblePointMinIndex
{
    _visiblePointMinIndex = visiblePointMinIndex;
    [self setNeedsDisplay:YES];
}

- (void)setVisiblePointMaxIndex:(NSUInteger)visiblePointMaxIndex
{
    _visiblePointMaxIndex = visiblePointMaxIndex;
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

- (void)setColorScaleMaxNA:(double)colorScaleMaxNA
{
    _colorScaleMaxNA = colorScaleMaxNA;
    [self setNeedsDisplay:YES];
}

- (void)setColorScaleMinNA:(double)colorScaleMinNA
{
    _colorScaleMinNA = colorScaleMinNA;
    [self setNeedsDisplay:YES];
}

- (void)updateTrackingAreas
{
    [super updateTrackingAreas];
    if (_trackingArea != nil) {
        [self removeTrackingArea:_trackingArea];
    }
    _trackingArea = [[NSTrackingArea alloc] initWithRect:NSZeroRect
                                                 options:(NSTrackingMouseMoved | NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect)
                                                   owner:self
                                                userInfo:nil];
    [self addTrackingArea:_trackingArea];
}

- (CGFloat)xPositionForScanIndex:(NSUInteger)scanIndex inPlotRect:(NSRect)plotRect
{
    NSUInteger minScan = [self normalizedVisibleScanMin];
    NSUInteger maxScan = [self normalizedVisibleScanMax];
    CGFloat fraction = (maxScan > minScan) ? (CGFloat)((double)scanIndex - (double)minScan) / (CGFloat)(maxScan - minScan) : 0.0;
    return plotRect.origin.x + (fraction * plotRect.size.width);
}

- (CGFloat)yPositionForPointIndex:(NSUInteger)pointIndex inPlotRect:(NSRect)plotRect
{
    NSUInteger minPoint = [self normalizedVisiblePointMin];
    NSUInteger maxPoint = [self normalizedVisiblePointMax];
    CGFloat fraction = (maxPoint > minPoint) ? (CGFloat)((double)pointIndex - (double)minPoint) / (CGFloat)(maxPoint - minPoint) : 0.0;
    return plotRect.origin.y + plotRect.size.height - (fraction * plotRect.size.height);
}

- (NSUInteger)normalizedVisibleScanMin
{
    if (self.scanCount == 0U) {
        return 0U;
    }
    return MIN(self.visibleScanMinIndex, self.scanCount - 1U);
}

- (NSUInteger)normalizedVisibleScanMax
{
    if (self.scanCount == 0U) {
        return 0U;
    }
    NSUInteger fallback = self.scanCount - 1U;
    NSUInteger maxScan = (self.visibleScanMaxIndex == NSNotFound) ? fallback : MIN(self.visibleScanMaxIndex, fallback);
    NSUInteger minScan = [self normalizedVisibleScanMin];
    return MAX(maxScan, minScan + (minScan < fallback ? 1U : 0U));
}

- (NSUInteger)normalizedVisiblePointMin
{
    if (self.pointCount == 0U) {
        return 0U;
    }
    return MIN(self.visiblePointMinIndex, self.pointCount - 1U);
}

- (NSUInteger)normalizedVisiblePointMax
{
    if (self.pointCount == 0U) {
        return 0U;
    }
    NSUInteger fallback = self.pointCount - 1U;
    NSUInteger maxPoint = (self.visiblePointMaxIndex == NSNotFound) ? fallback : MIN(self.visiblePointMaxIndex, fallback);
    NSUInteger minPoint = [self normalizedVisiblePointMin];
    return MAX(maxPoint, minPoint + (minPoint < fallback ? 1U : 0U));
}

- (void)addVoltageTickPointIndex:(NSUInteger)pointIndex
                         toArray:(NSMutableArray<NSNumber *> *)indexes
                         minPoint:(NSUInteger)minPoint
                         maxPoint:(NSUInteger)maxPoint
{
    if (pointIndex < minPoint || pointIndex > maxPoint) {
        return;
    }
    for (NSNumber *number in indexes) {
        if (number.unsignedIntegerValue == pointIndex) {
            return;
        }
    }
    [indexes addObject:@(pointIndex)];
}

- (NSUInteger)pointIndexNearestVoltageValue:(double)value minPoint:(NSUInteger)minPoint maxPoint:(NSUInteger)maxPoint
{
    const float *voltage = self.voltageData.bytes;
    NSUInteger bestIndex = minPoint;
    double bestDistance = DBL_MAX;

    for (NSUInteger pointIndex = minPoint; pointIndex <= maxPoint; ++pointIndex) {
        double distance = fabs((double)voltage[pointIndex] - value);
        if (distance < bestDistance) {
            bestDistance = distance;
            bestIndex = pointIndex;
        }
    }

    return bestIndex;
}

- (NSArray<NSNumber *> *)voltageTickPointIndexesFromMinPoint:(NSUInteger)minPoint maxPoint:(NSUInteger)maxPoint
{
    const float *voltage = self.voltageData.bytes;
    NSMutableArray<NSNumber *> *indexes = [NSMutableArray array];
    float voltageMin = voltage[minPoint];
    float voltageMax = voltage[minPoint];
    float epsilon;
    int segmentDirection = 0;
    BOOL hasSegment = NO;

    [self addVoltageTickPointIndex:minPoint toArray:indexes minPoint:minPoint maxPoint:maxPoint];
    [self addVoltageTickPointIndex:maxPoint toArray:indexes minPoint:minPoint maxPoint:maxPoint];

    for (NSUInteger pointIndex = minPoint + 1U; pointIndex <= maxPoint; ++pointIndex) {
        voltageMin = MIN(voltageMin, voltage[pointIndex]);
        voltageMax = MAX(voltageMax, voltage[pointIndex]);
    }

    epsilon = MAX(1.0e-6f, (voltageMax - voltageMin) * 1.0e-5f);
    [self addVoltageTickPointIndex:[self pointIndexNearestVoltageValue:voltageMin minPoint:minPoint maxPoint:maxPoint]
                           toArray:indexes
                          minPoint:minPoint
                          maxPoint:maxPoint];
    [self addVoltageTickPointIndex:[self pointIndexNearestVoltageValue:voltageMax minPoint:minPoint maxPoint:maxPoint]
                           toArray:indexes
                          minPoint:minPoint
                          maxPoint:maxPoint];
    if (voltageMin <= 0.0f && voltageMax >= 0.0f) {
        [self addVoltageTickPointIndex:[self pointIndexNearestVoltageValue:0.0 minPoint:minPoint maxPoint:maxPoint]
                               toArray:indexes
                              minPoint:minPoint
                              maxPoint:maxPoint];
    }

    for (NSUInteger pointIndex = minPoint + 1U; pointIndex <= maxPoint; ++pointIndex) {
        int direction = HDCVVoltageStepDirection(voltage[pointIndex - 1U], voltage[pointIndex], epsilon);
        if (!hasSegment) {
            segmentDirection = direction;
            hasSegment = YES;
            continue;
        }
        if (direction != segmentDirection) {
            [self addVoltageTickPointIndex:pointIndex - 1U toArray:indexes minPoint:minPoint maxPoint:maxPoint];
            segmentDirection = direction;
        }
    }

    {
        NSUInteger tickCount = MIN((NSUInteger)6U, maxPoint - minPoint + 1U);
        for (NSUInteger tick = 0U; tick < tickCount; ++tick) {
            NSUInteger pointIndex = (tickCount == 1U)
                ? minPoint
                : minPoint + (NSUInteger)llround((double)tick * (double)(maxPoint - minPoint) / (double)(tickCount - 1U));
            [self addVoltageTickPointIndex:pointIndex toArray:indexes minPoint:minPoint maxPoint:maxPoint];
        }
    }

    return [indexes sortedArrayUsingFunction:HDCVCompareNSNumberDouble context:NULL];
}

- (BOOL)scanIndex:(NSUInteger *)outScanIndex pointIndex:(NSUInteger *)outPointIndex fromPoint:(NSPoint)point
{
    NSRect plotRect = [self plotRect];
    if (!NSPointInRect(point, plotRect) || self.scanCount == 0U || self.pointCount == 0U) {
        return NO;
    }

    NSUInteger minScan = [self normalizedVisibleScanMin];
    NSUInteger maxScan = [self normalizedVisibleScanMax];
    NSUInteger minPoint = [self normalizedVisiblePointMin];
    NSUInteger maxPoint = [self normalizedVisiblePointMax];
    CGFloat xFraction = (point.x - plotRect.origin.x) / plotRect.size.width;
    CGFloat yFraction = 1.0 - ((point.y - plotRect.origin.y) / plotRect.size.height);
    if (outScanIndex != NULL) {
        *outScanIndex = minScan + (NSUInteger)llround(MAX(0.0, MIN(1.0, xFraction)) * (double)(maxScan - minScan));
    }
    if (outPointIndex != NULL) {
        *outPointIndex = minPoint + (NSUInteger)llround(MAX(0.0, MIN(1.0, yFraction)) * (double)(maxPoint - minPoint));
    }
    return YES;
}

- (NSString *)axisEditStringForTarget:(HDCVAxisEditTarget)target
{
    NSUInteger minPoint = [self normalizedVisiblePointMin];
    NSUInteger maxPoint = [self normalizedVisiblePointMax];
    const float *voltage = self.voltageData.bytes;

    if (target == HDCVAxisEditTargetXMin && self.xTickLabels.count > 0U) {
        return self.xTickLabels.firstObject;
    }
    if (target == HDCVAxisEditTargetXMax && self.xTickLabels.count > 0U) {
        return self.xTickLabels.lastObject;
    }
    if (self.voltageData.length >= self.pointCount * sizeof(float) && self.pointCount > 0U) {
        if (target == HDCVAxisEditTargetYMin) {
            return [NSString stringWithFormat:@"%.3f V", voltage[minPoint]];
        }
        if (target == HDCVAxisEditTargetYMax) {
            return [NSString stringWithFormat:@"%.3f V", voltage[maxPoint]];
        }
    }
    if (target == HDCVAxisEditTargetColorMax) {
        return [NSString stringWithFormat:@"%.3f nA", self.colorScaleMaxNA];
    }
    if (target == HDCVAxisEditTargetColorMin) {
        return [NSString stringWithFormat:@"%.3f nA", self.colorScaleMinNA];
    }
    return @"0";
}

- (NSRect)legendRectForPlotRect:(NSRect)plotRect
{
    return NSMakeRect(NSMaxX(plotRect) + 14.0, plotRect.origin.y, 14.0, plotRect.size.height);
}

- (NSRect)axisEditRectForTarget:(HDCVAxisEditTarget)target
                       plotRect:(NSRect)plotRect
                     attributes:(NSDictionary<NSAttributedStringKey, id> *)attributes
{
    NSString *label = [self axisEditStringForTarget:target];
    NSSize size = [label sizeWithAttributes:attributes];

    if (target == HDCVAxisEditTargetColorMax || target == HDCVAxisEditTargetColorMin) {
        NSRect legendRect = [self legendRectForPlotRect:plotRect];
        CGFloat y = (target == HDCVAxisEditTargetColorMax)
            ? legendRect.origin.y - 3.0
            : NSMaxY(legendRect) - size.height - 1.0;
        return NSInsetRect(NSMakeRect(NSMaxX(legendRect) + 4.0, y, MAX(size.width, 62.0), MAX(size.height, 16.0)), -12.0, -8.0);
    }

    if ((target == HDCVAxisEditTargetXMin || target == HDCVAxisEditTargetXMax) &&
        self.xTickFractions.count > 0U) {
        CGFloat fraction = (target == HDCVAxisEditTargetXMin)
            ? self.xTickFractions.firstObject.doubleValue
            : self.xTickFractions.lastObject.doubleValue;
        CGFloat x = plotRect.origin.x + (fraction * plotRect.size.width) - (size.width * 0.5);
        CGFloat y = NSMaxY(plotRect) + 20.0;
        return NSInsetRect(NSMakeRect(x, y, MAX(size.width, 56.0), MAX(size.height, 16.0)), -16.0, -9.0);
    }

    if (target == HDCVAxisEditTargetYMin || target == HDCVAxisEditTargetYMax) {
        CGFloat y = (target == HDCVAxisEditTargetYMin)
            ? NSMaxY(plotRect) - (size.height * 0.5)
            : plotRect.origin.y - (size.height * 0.5);
        return NSInsetRect(NSMakeRect(6.0, y, MAX(size.width, 56.0), MAX(size.height, 16.0)), -16.0, -9.0);
    }

    return NSZeroRect;
}

- (HDCVAxisEditTarget)axisEditTargetForPoint:(NSPoint)point editorRect:(NSRect *)outRect
{
    NSRect plotRect = [self plotRect];
    NSDictionary *tickAttrs = [self labelAttributesWithColor:HDCVMutedText() size:9.0 weight:NSFontWeightRegular];
    HDCVAxisEditTarget targets[] = {
        HDCVAxisEditTargetXMin,
        HDCVAxisEditTargetXMax,
        HDCVAxisEditTargetYMin,
        HDCVAxisEditTargetYMax,
        HDCVAxisEditTargetColorMin,
        HDCVAxisEditTargetColorMax
    };

    for (NSUInteger i = 0U; i < sizeof(targets) / sizeof(targets[0]); ++i) {
        NSRect rect = [self axisEditRectForTarget:targets[i] plotRect:plotRect attributes:tickAttrs];
        if (!NSEqualRects(rect, NSZeroRect) && NSPointInRect(point, rect)) {
            if (outRect != NULL) {
                *outRect = rect;
            }
            return targets[i];
        }
    }
    return HDCVAxisEditTargetNone;
}

- (void)finishAxisEditing
{
    if (_axisEditor == nil || _activeAxisEditTarget == HDCVAxisEditTargetNone) {
        return;
    }

    NSTextField *editor = _axisEditor;
    HDCVAxisEditTarget target = _activeAxisEditTarget;
    double value = 0.0;
    _axisEditor = nil;
    _activeAxisEditTarget = HDCVAxisEditTargetNone;
    [editor removeFromSuperview];

    if (HDCVParseLeadingDouble(editor.stringValue, &value)) {
        [self.delegate heatmapView:self didEditAxisTarget:target value:value];
    }
}

- (void)axisEditorAction:(id)sender
{
    (void)sender;
    [self finishAxisEditing];
    [self.window makeFirstResponder:self];
}

- (void)controlTextDidEndEditing:(NSNotification *)notification
{
    (void)notification;
    [self finishAxisEditing];
}

- (void)beginAxisEditingTarget:(HDCVAxisEditTarget)target rect:(NSRect)rect
{
    [_axisEditor removeFromSuperview];
    _activeAxisEditTarget = target;

    NSRect editorRect = NSInsetRect(rect, -4.0, -2.0);
    editorRect.size.width = MAX(editorRect.size.width, 74.0);
    editorRect.size.height = 22.0;
    editorRect.origin.x = MAX(2.0, MIN(editorRect.origin.x, self.bounds.size.width - editorRect.size.width - 2.0));
    editorRect.origin.y = MAX(2.0, MIN(editorRect.origin.y, self.bounds.size.height - editorRect.size.height - 2.0));

    _axisEditor = [[NSTextField alloc] initWithFrame:editorRect];
    _axisEditor.font = [NSFont monospacedDigitSystemFontOfSize:11.0 weight:NSFontWeightMedium];
    _axisEditor.alignment = NSTextAlignmentCenter;
    _axisEditor.bezelStyle = NSTextFieldRoundedBezel;
    _axisEditor.controlSize = NSControlSizeSmall;
    _axisEditor.stringValue = [self axisEditStringForTarget:target];
    _axisEditor.target = self;
    _axisEditor.action = @selector(axisEditorAction:);
    [self addSubview:_axisEditor];
    [self.window makeFirstResponder:_axisEditor];
    [_axisEditor selectText:nil];
}

- (HDCVHeatmapDragTarget)dragTargetForPoint:(NSPoint)point
{
    NSRect plotRect = [self plotRect];
    CGFloat tolerance = 7.0;
    CGFloat selectedX;
    CGFloat selectedY;
    CGFloat backgroundX = CGFLOAT_MAX;
    CGFloat selectedXDistance;
    CGFloat backgroundXDistance;
    BOOL nearSelectedX;
    BOOL nearSelectedY;
    BOOL nearBackgroundX;
    BOOL selectedVisible;
    BOOL backgroundVisible;

    if (!NSPointInRect(point, plotRect) || self.scanCount == 0U || self.pointCount == 0U) {
        return HDCVHeatmapDragTargetNone;
    }

    selectedVisible = self.selectedScanIndex >= [self normalizedVisibleScanMin] &&
        self.selectedScanIndex <= [self normalizedVisibleScanMax] &&
        self.selectedPointIndex >= [self normalizedVisiblePointMin] &&
        self.selectedPointIndex <= [self normalizedVisiblePointMax];
    backgroundVisible = self.backgroundScanIndex != NSNotFound &&
        self.backgroundScanIndex >= [self normalizedVisibleScanMin] &&
        self.backgroundScanIndex <= [self normalizedVisibleScanMax];

    selectedX = selectedVisible ? [self xPositionForScanIndex:self.selectedScanIndex inPlotRect:plotRect] : CGFLOAT_MAX;
    selectedY = selectedVisible ? [self yPositionForPointIndex:self.selectedPointIndex inPlotRect:plotRect] : CGFLOAT_MAX;
    if (backgroundVisible) {
        backgroundX = [self xPositionForScanIndex:self.backgroundScanIndex inPlotRect:plotRect];
    }

    selectedXDistance = fabs(point.x - selectedX);
    backgroundXDistance = fabs(point.x - backgroundX);
    nearSelectedX = selectedVisible && selectedXDistance <= tolerance;
    nearSelectedY = selectedVisible && fabs(point.y - selectedY) <= tolerance;
    nearBackgroundX = backgroundVisible && backgroundXDistance <= tolerance;

    if (nearSelectedX && nearSelectedY) {
        return HDCVHeatmapDragTargetSelectionXY;
    }
    if (nearSelectedX && (!nearBackgroundX || selectedXDistance <= backgroundXDistance)) {
        return HDCVHeatmapDragTargetSelectionX;
    }
    if (nearSelectedY) {
        return HDCVHeatmapDragTargetSelectionY;
    }
    if (nearBackgroundX) {
        return HDCVHeatmapDragTargetBackgroundX;
    }
    return HDCVHeatmapDragTargetNone;
}

- (void)updateCursorForEvent:(NSEvent *)event
{
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    if ([self dragTargetForPoint:point] == HDCVHeatmapDragTargetNone) {
        [NSCursor.arrowCursor set];
    } else {
        [NSCursor.openHandCursor set];
    }
}

- (void)mouseMoved:(NSEvent *)event
{
    [self updateCursorForEvent:event];
}

- (void)mouseExited:(NSEvent *)event
{
    (void)event;
    [NSCursor.arrowCursor set];
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
        NSUInteger minScan = [self normalizedVisibleScanMin];
        NSUInteger maxScan = [self normalizedVisibleScanMax];
        NSUInteger minPoint = [self normalizedVisiblePointMin];
        NSUInteger maxPoint = [self normalizedVisiblePointMax];
        CGFloat imageWidth = MAX(self.image.size.width, 1.0);
        CGFloat imageHeight = MAX(self.image.size.height, 1.0);
        CGFloat scanDenominator = self.scanCount > 1U ? (CGFloat)(self.scanCount - 1U) : 1.0;
        CGFloat pointDenominator = self.pointCount > 1U ? (CGFloat)(self.pointCount - 1U) : 1.0;
        CGFloat sourceX = ((CGFloat)minScan / scanDenominator) * imageWidth;
        CGFloat sourceWidth = MAX(1.0, ((CGFloat)(maxScan - minScan) / scanDenominator) * imageWidth);
        CGFloat sourceY = ((CGFloat)minPoint / pointDenominator) * imageHeight;
        CGFloat sourceHeight = MAX(1.0, ((CGFloat)(maxPoint - minPoint) / pointDenominator) * imageHeight);
        NSRect sourceRect = NSMakeRect(sourceX, sourceY, sourceWidth, sourceHeight);
        [self.image drawInRect:plotRect
                      fromRect:sourceRect
                     operation:NSCompositingOperationSourceOver
                      fraction:1.0
                respectFlipped:YES
                         hints:nil];
    }

    {
        NSRect legendRect = [self legendRectForPlotRect:plotRect];
        NSUInteger steps = MAX((NSUInteger)plotRect.size.height, 1U);
        for (NSUInteger i = 0U; i < steps; ++i) {
            CGFloat fraction = steps > 1U ? (CGFloat)i / (CGFloat)(steps - 1U) : 0.0;
            float r;
            float g;
            float b;
            HDCVHeatmapRGBForNormalized((float)(1.0 - (2.0 * fraction)), &r, &g, &b);
            [[NSColor colorWithRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:1.0] setFill];
            NSRectFill(NSMakeRect(legendRect.origin.x, legendRect.origin.y + (CGFloat)i, legendRect.size.width, 1.0));
        }
        [[NSColor colorWithWhite:0.72 alpha:1.0] setStroke];
        NSBezierPath *legendBorder = [NSBezierPath bezierPathWithRoundedRect:legendRect xRadius:4.0 yRadius:4.0];
        legendBorder.lineWidth = 0.8;
        [legendBorder stroke];

        NSString *topLabel = [NSString stringWithFormat:@"%+.0f nA", self.colorScaleMaxNA];
        NSString *middleLabel = @"0 nA";
        NSString *bottomLabel = [NSString stringWithFormat:@"%+.0f nA", self.colorScaleMinNA];
        [@"Current (nA)" drawAtPoint:NSMakePoint(NSMaxX(plotRect) + 2.0, plotRect.origin.y - 18.0) withAttributes:tickAttrs];
        [topLabel drawAtPoint:NSMakePoint(NSMaxX(legendRect) + 5.0, legendRect.origin.y - 2.0) withAttributes:tickAttrs];
        [middleLabel drawAtPoint:NSMakePoint(NSMaxX(legendRect) + 5.0, NSMidY(legendRect) - 6.0) withAttributes:tickAttrs];
        [bottomLabel drawAtPoint:NSMakePoint(NSMaxX(legendRect) + 5.0, NSMaxY(legendRect) - 13.0) withAttributes:tickAttrs];
    }

    if (self.scanCount > 0U &&
        self.backgroundScanIndex != NSNotFound &&
        self.backgroundScanIndex >= [self normalizedVisibleScanMin] &&
        self.backgroundScanIndex <= [self normalizedVisibleScanMax]) {
        CGFloat backgroundX = [self xPositionForScanIndex:self.backgroundScanIndex inPlotRect:plotRect];
        NSBezierPath *backgroundLine = [NSBezierPath bezierPath];
        [backgroundLine moveToPoint:NSMakePoint(backgroundX, plotRect.origin.y)];
        [backgroundLine lineToPoint:NSMakePoint(backgroundX, NSMaxY(plotRect))];
        backgroundLine.lineWidth = 1.2;
        CGFloat dashes[] = {3.0, 4.0};
        [backgroundLine setLineDash:dashes count:2 phase:0.0];
        [[HDCVAccentBlue() colorWithAlphaComponent:0.95] setStroke];
        [backgroundLine stroke];
    }

    if (self.scanCount > 0U &&
        self.pointCount > 0U &&
        self.selectedScanIndex >= [self normalizedVisibleScanMin] &&
        self.selectedScanIndex <= [self normalizedVisibleScanMax] &&
        self.selectedPointIndex >= [self normalizedVisiblePointMin] &&
        self.selectedPointIndex <= [self normalizedVisiblePointMax]) {
        CGFloat crossX = [self xPositionForScanIndex:self.selectedScanIndex inPlotRect:plotRect];
        CGFloat crossY = [self yPositionForPointIndex:self.selectedPointIndex inPlotRect:plotRect];

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

    [@"Time (s)" drawAtPoint:NSMakePoint(NSMidX(plotRect) - 22.0, NSMaxY(plotRect) + 8.0) withAttributes:axisAttrs];
    [@"Voltage (V)" drawAtPoint:NSMakePoint(8.0, 16.0) withAttributes:axisAttrs];

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
        NSUInteger minPoint = [self normalizedVisiblePointMin];
        NSUInteger maxPoint = [self normalizedVisiblePointMax];
        NSArray<NSNumber *> *tickIndexes = [self voltageTickPointIndexesFromMinPoint:minPoint maxPoint:maxPoint];
        CGFloat lastLabelY = -CGFLOAT_MAX;
        for (NSNumber *tickIndex in tickIndexes) {
            NSUInteger pointIndex = tickIndex.unsignedIntegerValue;
            CGFloat fraction = (maxPoint > minPoint) ? (CGFloat)(pointIndex - minPoint) / (CGFloat)(maxPoint - minPoint) : 0.0;
            CGFloat y = plotRect.origin.y + plotRect.size.height - (fraction * plotRect.size.height);
            NSString *label = [NSString stringWithFormat:@"%.2f V", voltage[pointIndex]];
            NSSize size = [label sizeWithAttributes:tickAttrs];

            NSBezierPath *grid = [NSBezierPath bezierPath];
            [grid moveToPoint:NSMakePoint(plotRect.origin.x, y)];
            [grid lineToPoint:NSMakePoint(NSMaxX(plotRect), y)];
            grid.lineWidth = 0.5;
            [HDCVSoftGridColor() setStroke];
            [grid stroke];

            if (fabs(y - lastLabelY) >= 15.0 || pointIndex == minPoint || pointIndex == maxPoint) {
                [label drawAtPoint:NSMakePoint(6.0, y - size.height * 0.5) withAttributes:tickAttrs];
                lastLabelY = y;
            }
        }
    }
}

- (void)updateSelectionFromEvent:(NSEvent *)event
{
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSUInteger scanIndex = 0U;
    NSUInteger pointIndex = 0U;
    if (![self scanIndex:&scanIndex pointIndex:&pointIndex fromPoint:point]) {
        return;
    }

    if (_activeDragTarget == HDCVHeatmapDragTargetBackgroundX) {
        [self.delegate heatmapView:self didDragBackgroundScanIndex:scanIndex];
    } else if (_activeDragTarget == HDCVHeatmapDragTargetSelectionX) {
        [self.delegate heatmapView:self didDragSelectionScanIndex:scanIndex pointIndex:pointIndex updateScan:YES updatePoint:NO];
    } else if (_activeDragTarget == HDCVHeatmapDragTargetSelectionY) {
        [self.delegate heatmapView:self didDragSelectionScanIndex:scanIndex pointIndex:pointIndex updateScan:NO updatePoint:YES];
    } else if (_activeDragTarget == HDCVHeatmapDragTargetSelectionXY) {
        [self.delegate heatmapView:self didDragSelectionScanIndex:scanIndex pointIndex:pointIndex updateScan:YES updatePoint:YES];
    }
}

- (void)mouseDown:(NSEvent *)event
{
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    if (event.clickCount >= 2) {
        NSRect editorRect = NSZeroRect;
        HDCVAxisEditTarget target = [self axisEditTargetForPoint:point editorRect:&editorRect];
        if (target != HDCVAxisEditTargetNone) {
            [self beginAxisEditingTarget:target rect:editorRect];
            return;
        }
    }
    _activeDragTarget = [self dragTargetForPoint:point];
    if (_activeDragTarget != HDCVHeatmapDragTargetNone) {
        [NSCursor.closedHandCursor set];
    }
}

- (void)mouseDragged:(NSEvent *)event
{
    if (_activeDragTarget != HDCVHeatmapDragTargetNone) {
        [NSCursor.closedHandCursor set];
        [self updateSelectionFromEvent:event];
    }
}

- (void)mouseUp:(NSEvent *)event
{
    (void)event;
    _activeDragTarget = HDCVHeatmapDragTargetNone;
}

@end

@implementation HDCVLinePlotView {
    HDCVLinePlotDragTarget _activeDragTarget;
    HDCVAxisEditTarget _activeAxisEditTarget;
    NSTextField *_axisEditor;
    NSTrackingArea *_trackingArea;
    BOOL _activePanDrag;
    NSPoint _panStartPoint;
    double _panStartXMin;
    double _panStartXMax;
    double _panStartYMin;
    double _panStartYMax;
}

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
        _activeDragTarget = HDCVLinePlotDragTargetNone;
        _activePanDrag = NO;
        self.wantsLayer = YES;
        self.layer.backgroundColor = NSColor.whiteColor.CGColor;
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

- (NSRect)plotRect
{
    return NSMakeRect(60.0, 62.0, MAX(40.0, self.bounds.size.width - 84.0), MAX(40.0, self.bounds.size.height - 98.0));
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

- (double)clampedYValueForPoint:(NSPoint)point
{
    NSRect plotRect = [self plotRect];
    double fraction = 1.0 - (double)((point.y - plotRect.origin.y) / plotRect.size.height);
    double clampedFraction = MAX(0.0, MIN(1.0, fraction));
    return self.yMin + ((self.yMax - self.yMin) * clampedFraction);
}

- (void)updateTrackingAreas
{
    [super updateTrackingAreas];
    if (_trackingArea != nil) {
        [self removeTrackingArea:_trackingArea];
    }
    _trackingArea = [[NSTrackingArea alloc] initWithRect:NSZeroRect
                                                 options:(NSTrackingMouseMoved | NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect)
                                                   owner:self
                                                userInfo:nil];
    [self addTrackingArea:_trackingArea];
}

- (CGFloat)xPositionForValue:(double)xValue inPlotRect:(NSRect)plotRect xMin:(double)xMin xRange:(double)xRange
{
    return plotRect.origin.x + (CGFloat)((xValue - xMin) / xRange) * plotRect.size.width;
}

- (BOOL)pointIsInPlotRect:(NSPoint)point
{
    return NSPointInRect(point, [self plotRect]);
}

- (void)dispatchNavigationXMin:(double)xMin xMax:(double)xMax yMin:(double)yMin yMax:(double)yMax
{
    double minRange = 1.0e-12;
    if (!self.viewNavigationEnabled ||
        !isfinite(xMin) || !isfinite(xMax) || !isfinite(yMin) || !isfinite(yMax) ||
        xMax - xMin <= minRange || yMax - yMin <= minRange) {
        return;
    }
    [self.delegate linePlotView:self didNavigateToXMin:xMin xMax:xMax yMin:yMin yMax:yMax];
}

- (void)dispatchPanFromPoint:(NSPoint)point
{
    NSRect plotRect = [self plotRect];
    double xRange = _panStartXMax - _panStartXMin;
    double yRange = _panStartYMax - _panStartYMin;
    double dx = ((double)(point.x - _panStartPoint.x) / MAX((double)plotRect.size.width, 1.0)) * xRange;
    double dy = ((double)(point.y - _panStartPoint.y) / MAX((double)plotRect.size.height, 1.0)) * yRange;
    [self dispatchNavigationXMin:_panStartXMin - dx
                            xMax:_panStartXMax - dx
                            yMin:_panStartYMin + dy
                            yMax:_panStartYMax + dy];
}

- (void)dispatchZoomWithFactor:(double)factor aroundPoint:(NSPoint)point
{
    NSRect plotRect = [self plotRect];
    double xRange = self.xMax - self.xMin;
    double yRange = self.yMax - self.yMin;
    double xFraction = ((double)(point.x - plotRect.origin.x) / MAX((double)plotRect.size.width, 1.0));
    double yFraction = 1.0 - ((double)(point.y - plotRect.origin.y) / MAX((double)plotRect.size.height, 1.0));
    double anchorX;
    double anchorY;

    if (!NSPointInRect(point, plotRect)) {
        xFraction = 0.5;
        yFraction = 0.5;
    }
    xFraction = MAX(0.0, MIN(1.0, xFraction));
    yFraction = MAX(0.0, MIN(1.0, yFraction));
    factor = MAX(0.05, MIN(20.0, factor));

    anchorX = self.xMin + (xRange * xFraction);
    anchorY = self.yMin + (yRange * yFraction);
    [self dispatchNavigationXMin:anchorX - ((anchorX - self.xMin) * factor)
                            xMax:anchorX + ((self.xMax - anchorX) * factor)
                            yMin:anchorY - ((anchorY - self.yMin) * factor)
                            yMax:anchorY + ((self.yMax - anchorY) * factor)];
}

- (NSString *)axisEditStringForTarget:(HDCVAxisEditTarget)target
{
    switch (target) {
        case HDCVAxisEditTargetXMin:
            return [NSString stringWithFormat:self.xTickFormat, self.xMin];
        case HDCVAxisEditTargetXMax:
            return [NSString stringWithFormat:self.xTickFormat, self.xMax];
        case HDCVAxisEditTargetYMin:
            return [NSString stringWithFormat:self.yTickFormat, self.yMin];
        case HDCVAxisEditTargetYMax:
            return [NSString stringWithFormat:self.yTickFormat, self.yMax];
        default:
            return @"0";
    }
}

- (NSRect)axisEditRectForTarget:(HDCVAxisEditTarget)target
                       plotRect:(NSRect)plotRect
                     attributes:(NSDictionary<NSAttributedStringKey, id> *)attributes
{
    NSString *label = [self axisEditStringForTarget:target];
    NSSize size = [label sizeWithAttributes:attributes];

    if (target == HDCVAxisEditTargetXMin || target == HDCVAxisEditTargetXMax) {
        CGFloat fraction = (target == HDCVAxisEditTargetXMin) ? 0.0 : 1.0;
        CGFloat x = plotRect.origin.x + (fraction * plotRect.size.width) - (size.width * 0.5);
        CGFloat y = NSMaxY(plotRect) + 20.0;
        return NSInsetRect(NSMakeRect(x, y, MAX(size.width, 56.0), MAX(size.height, 16.0)), -16.0, -9.0);
    }

    if (target == HDCVAxisEditTargetYMin || target == HDCVAxisEditTargetYMax) {
        CGFloat y = (target == HDCVAxisEditTargetYMax)
            ? plotRect.origin.y - (size.height * 0.5)
            : NSMaxY(plotRect) - (size.height * 0.5);
        return NSInsetRect(NSMakeRect(6.0, y, MAX(size.width, 56.0), MAX(size.height, 16.0)), -16.0, -9.0);
    }

    return NSZeroRect;
}

- (HDCVAxisEditTarget)axisEditTargetForPoint:(NSPoint)point editorRect:(NSRect *)outRect
{
    NSRect plotRect = [self plotRect];
    NSDictionary *tickAttrs = [self labelAttributesWithColor:HDCVMutedText() size:9.0 weight:NSFontWeightRegular];
    HDCVAxisEditTarget targets[] = {
        HDCVAxisEditTargetXMin,
        HDCVAxisEditTargetXMax,
        HDCVAxisEditTargetYMin,
        HDCVAxisEditTargetYMax
    };

    for (NSUInteger i = 0U; i < sizeof(targets) / sizeof(targets[0]); ++i) {
        NSRect rect = [self axisEditRectForTarget:targets[i] plotRect:plotRect attributes:tickAttrs];
        if (!NSEqualRects(rect, NSZeroRect) && NSPointInRect(point, rect)) {
            if (outRect != NULL) {
                *outRect = rect;
            }
            return targets[i];
        }
    }
    return HDCVAxisEditTargetNone;
}

- (void)finishAxisEditing
{
    if (_axisEditor == nil || _activeAxisEditTarget == HDCVAxisEditTargetNone) {
        return;
    }

    NSTextField *editor = _axisEditor;
    HDCVAxisEditTarget target = _activeAxisEditTarget;
    double value = 0.0;
    _axisEditor = nil;
    _activeAxisEditTarget = HDCVAxisEditTargetNone;
    [editor removeFromSuperview];

    if (HDCVParseLeadingDouble(editor.stringValue, &value)) {
        [self.delegate linePlotView:self didEditAxisTarget:target value:value];
    }
}

- (void)axisEditorAction:(id)sender
{
    (void)sender;
    [self finishAxisEditing];
    [self.window makeFirstResponder:self];
}

- (void)controlTextDidEndEditing:(NSNotification *)notification
{
    (void)notification;
    [self finishAxisEditing];
}

- (void)beginAxisEditingTarget:(HDCVAxisEditTarget)target rect:(NSRect)rect
{
    [_axisEditor removeFromSuperview];
    _activeAxisEditTarget = target;

    NSRect editorRect = NSInsetRect(rect, -4.0, -2.0);
    editorRect.size.width = MAX(editorRect.size.width, 74.0);
    editorRect.size.height = 22.0;
    editorRect.origin.x = MAX(2.0, MIN(editorRect.origin.x, self.bounds.size.width - editorRect.size.width - 2.0));
    editorRect.origin.y = MAX(2.0, MIN(editorRect.origin.y, self.bounds.size.height - editorRect.size.height - 2.0));

    _axisEditor = [[NSTextField alloc] initWithFrame:editorRect];
    _axisEditor.font = [NSFont monospacedDigitSystemFontOfSize:11.0 weight:NSFontWeightMedium];
    _axisEditor.alignment = NSTextAlignmentCenter;
    _axisEditor.bezelStyle = NSTextFieldRoundedBezel;
    _axisEditor.controlSize = NSControlSizeSmall;
    _axisEditor.stringValue = [self axisEditStringForTarget:target];
    _axisEditor.target = self;
    _axisEditor.action = @selector(axisEditorAction:);
    [self addSubview:_axisEditor];
    [self.window makeFirstResponder:_axisEditor];
    [_axisEditor selectText:nil];
}

- (HDCVLinePlotDragTarget)dragTargetForPoint:(NSPoint)point
{
    NSRect plotRect = [self plotRect];
    double xMin = self.xMin;
    double xMax = self.xMax;
    double xRange;
    CGFloat tolerance = 7.0;
    CGFloat selectedX;
    CGFloat backgroundX = CGFLOAT_MAX;
    CGFloat selectedDistance;
    CGFloat backgroundDistance;
    BOOL nearSelected;
    BOOL nearBackground;

    if (!NSPointInRect(point, plotRect) || self.interactionMode != HDCVLinePlotInteractionModeSelectX) {
        return HDCVLinePlotDragTargetNone;
    }
    if (xMax <= xMin) {
        xMax = xMin + 1.0;
    }
    xRange = xMax - xMin;

    selectedX = [self xPositionForValue:self.selectedXValue inPlotRect:plotRect xMin:xMin xRange:xRange];
    if (self.showsBackgroundX) {
        backgroundX = [self xPositionForValue:self.backgroundXValue inPlotRect:plotRect xMin:xMin xRange:xRange];
    }
    selectedDistance = fabs(point.x - selectedX);
    backgroundDistance = fabs(point.x - backgroundX);
    nearSelected = self.showsSelection && selectedDistance <= tolerance;
    nearBackground = self.showsBackgroundX && backgroundDistance <= tolerance;

    if (nearSelected && (!nearBackground || selectedDistance <= backgroundDistance)) {
        return HDCVLinePlotDragTargetSelectedX;
    }
    if (nearBackground) {
        return HDCVLinePlotDragTargetBackgroundX;
    }
    return HDCVLinePlotDragTargetNone;
}

- (void)updateCursorForEvent:(NSEvent *)event
{
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    if ([self dragTargetForPoint:point] != HDCVLinePlotDragTargetNone ||
        (self.viewNavigationEnabled && [self pointIsInPlotRect:point])) {
        [NSCursor.openHandCursor set];
    } else {
        [NSCursor.arrowCursor set];
    }
}

- (void)mouseMoved:(NSEvent *)event
{
    [self updateCursorForEvent:event];
}

- (void)mouseExited:(NSEvent *)event
{
    (void)event;
    [NSCursor.arrowCursor set];
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

    NSArray<NSNumber *> *xTicks = HDCVAxisTickValues(xMin, xMax, 5U, YES);
    NSArray<NSNumber *> *yTicks = HDCVAxisTickValues(yMin, yMax, 5U, YES);

    for (NSNumber *tickValue in xTicks) {
        double xValue = tickValue.doubleValue;
        CGFloat fraction = (CGFloat)((xValue - xMin) / xRange);
        NSString *xLabel = [NSString stringWithFormat:self.xTickFormat, xValue];
        NSSize xSize = [xLabel sizeWithAttributes:tickAttrs];
        CGFloat x = plotRect.origin.x + (fraction * plotRect.size.width);

        [HDCVSoftGridColor() setStroke];
        NSBezierPath *verticalGrid = [NSBezierPath bezierPath];
        [verticalGrid moveToPoint:NSMakePoint(x, plotRect.origin.y)];
        [verticalGrid lineToPoint:NSMakePoint(x, NSMaxY(plotRect))];
        verticalGrid.lineWidth = 0.5;
        [verticalGrid stroke];

        [xLabel drawAtPoint:NSMakePoint(x - xSize.width * 0.5, NSMaxY(plotRect) + 20.0) withAttributes:tickAttrs];
    }

    for (NSNumber *tickValue in yTicks) {
        double yValue = tickValue.doubleValue;
        CGFloat fraction = (CGFloat)((yValue - yMin) / yRange);
        NSString *yLabel = [NSString stringWithFormat:self.yTickFormat, yValue];
        NSSize ySize = [yLabel sizeWithAttributes:tickAttrs];
        CGFloat y = plotRect.origin.y + plotRect.size.height - (fraction * plotRect.size.height);

        [HDCVSoftGridColor() setStroke];
        NSBezierPath *horizontalGrid = [NSBezierPath bezierPath];
        [horizontalGrid moveToPoint:NSMakePoint(plotRect.origin.x, y)];
        [horizontalGrid lineToPoint:NSMakePoint(NSMaxX(plotRect), y)];
        horizontalGrid.lineWidth = 0.5;
        [horizontalGrid stroke];

        [yLabel drawAtPoint:NSMakePoint(6.0, y - ySize.height * 0.5) withAttributes:tickAttrs];
    }

    [NSGraphicsContext saveGraphicsState];
    [[NSBezierPath bezierPathWithRect:plotRect] addClip];

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

    if (self.showsBackgroundX) {
        CGFloat backgroundX = [self xPositionForValue:self.backgroundXValue inPlotRect:plotRect xMin:xMin xRange:xRange];
        NSBezierPath *backgroundLine = [NSBezierPath bezierPath];
        [backgroundLine moveToPoint:NSMakePoint(backgroundX, plotRect.origin.y)];
        [backgroundLine lineToPoint:NSMakePoint(backgroundX, NSMaxY(plotRect))];
        backgroundLine.lineWidth = 1.15;
        CGFloat dashes[] = {3.0, 4.0};
        [backgroundLine setLineDash:dashes count:2 phase:0.0];
        [[HDCVAccentBlue() colorWithAlphaComponent:0.92] setStroke];
        [backgroundLine stroke];
    }

    {
        BOOL monotonicX = YES;
        double previousX = [self.dataSource linePlotView:self xValueAtIndex:0U];
        NSUInteger firstVisible = NSNotFound;
        NSUInteger lastVisible = 0U;
        NSUInteger visibleCount = 0U;

        for (NSUInteger i = 0U; i < sampleCount; ++i) {
            double xValue = (i == 0U) ? previousX : [self.dataSource linePlotView:self xValueAtIndex:i];
            if (i > 0U && xValue < previousX) {
                monotonicX = NO;
            }
            previousX = xValue;

            if (xValue >= xMin && xValue <= xMax) {
                if (firstVisible == NSNotFound) {
                    firstVisible = i;
                }
                lastVisible = i;
                visibleCount += 1U;
            }
        }

        [self.strokeColor setStroke];

        NSUInteger directThreshold = MAX((NSUInteger)10000U, (NSUInteger)ceil(plotRect.size.width) * 12U);
        if (!monotonicX || visibleCount <= directThreshold || firstVisible == NSNotFound) {
            NSUInteger startIndex = 0U;
            NSUInteger endIndex = sampleCount - 1U;
            if (monotonicX && firstVisible != NSNotFound) {
                startIndex = (firstVisible > 0U) ? firstVisible - 1U : firstVisible;
                endIndex = MIN(sampleCount - 1U, lastVisible + 1U);
            }

            NSBezierPath *path = [NSBezierPath bezierPath];
            path.lineWidth = 1.9;
            BOOL hasPoint = NO;
            for (NSUInteger i = startIndex; i <= endIndex; ++i) {
                double xValue = [self.dataSource linePlotView:self xValueAtIndex:i];
                double yValue = [self.dataSource linePlotView:self yValueAtIndex:i];
                if (!isfinite(xValue) || !isfinite(yValue)) {
                    hasPoint = NO;
                    continue;
                }
                CGFloat x = plotRect.origin.x + (CGFloat)((xValue - xMin) / xRange) * plotRect.size.width;
                CGFloat y = plotRect.origin.y + plotRect.size.height - (CGFloat)((yValue - yMin) / yRange) * plotRect.size.height;
                if (!hasPoint) {
                    [path moveToPoint:NSMakePoint(x, y)];
                    hasPoint = YES;
                } else {
                    [path lineToPoint:NSMakePoint(x, y)];
                }
            }
            [path stroke];
        } else {
            NSUInteger binCount = MAX((NSUInteger)ceil(plotRect.size.width), 1U);
            double *minValues = (double *)malloc(binCount * sizeof(*minValues));
            double *maxValues = (double *)malloc(binCount * sizeof(*maxValues));
            unsigned char *hasValues = (unsigned char *)calloc(binCount, sizeof(*hasValues));

            if (minValues != NULL && maxValues != NULL && hasValues != NULL) {
                for (NSUInteger bin = 0U; bin < binCount; ++bin) {
                    minValues[bin] = DBL_MAX;
                    maxValues[bin] = -DBL_MAX;
                }

                for (NSUInteger i = firstVisible; i <= lastVisible; ++i) {
                    double xValue = [self.dataSource linePlotView:self xValueAtIndex:i];
                    double yValue = [self.dataSource linePlotView:self yValueAtIndex:i];
                    if (!isfinite(xValue) || !isfinite(yValue)) {
                        continue;
                    }
                    double fraction = (xValue - xMin) / xRange;
                    NSInteger bin = (NSInteger)floor(fraction * (double)binCount);
                    bin = MAX((NSInteger)0, MIN((NSInteger)binCount - 1, bin));
                    if (!hasValues[bin]) {
                        minValues[bin] = yValue;
                        maxValues[bin] = yValue;
                        hasValues[bin] = 1U;
                    } else {
                        minValues[bin] = MIN(minValues[bin], yValue);
                        maxValues[bin] = MAX(maxValues[bin], yValue);
                    }
                }

                NSBezierPath *envelope = [NSBezierPath bezierPath];
                envelope.lineWidth = 1.15;
                for (NSUInteger bin = 0U; bin < binCount; ++bin) {
                    if (!hasValues[bin]) {
                        continue;
                    }
                    CGFloat x = plotRect.origin.x + ((CGFloat)bin + 0.5) / (CGFloat)binCount * plotRect.size.width;
                    CGFloat y1 = plotRect.origin.y + plotRect.size.height - (CGFloat)((minValues[bin] - yMin) / yRange) * plotRect.size.height;
                    CGFloat y2 = plotRect.origin.y + plotRect.size.height - (CGFloat)((maxValues[bin] - yMin) / yRange) * plotRect.size.height;
                    if (fabs(y1 - y2) < 1.0) {
                        y1 -= 0.5;
                        y2 += 0.5;
                    }
                    [envelope moveToPoint:NSMakePoint(x, y1)];
                    [envelope lineToPoint:NSMakePoint(x, y2)];
                }
                [[self.strokeColor colorWithAlphaComponent:0.86] setStroke];
                [envelope stroke];
            } else {
                NSBezierPath *path = [NSBezierPath bezierPath];
                path.lineWidth = 1.9;
                BOOL hasPoint = NO;
                for (NSUInteger i = 0U; i < sampleCount; ++i) {
                    double xValue = [self.dataSource linePlotView:self xValueAtIndex:i];
                    double yValue = [self.dataSource linePlotView:self yValueAtIndex:i];
                    if (!isfinite(xValue) || !isfinite(yValue)) {
                        hasPoint = NO;
                        continue;
                    }
                    CGFloat x = plotRect.origin.x + (CGFloat)((xValue - xMin) / xRange) * plotRect.size.width;
                    CGFloat y = plotRect.origin.y + plotRect.size.height - (CGFloat)((yValue - yMin) / yRange) * plotRect.size.height;
                    if (!hasPoint) {
                        [path moveToPoint:NSMakePoint(x, y)];
                        hasPoint = YES;
                    } else {
                        [path lineToPoint:NSMakePoint(x, y)];
                    }
                }
                [path stroke];
            }

            free(minValues);
            free(maxValues);
            free(hasValues);
        }
    }

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
    [NSGraphicsContext restoreGraphicsState];
}

- (void)dispatchSelectionForEvent:(NSEvent *)event
{
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSRect plotRect = [self plotRect];
    if (!NSPointInRect(point, plotRect) || self.interactionMode != HDCVLinePlotInteractionModeSelectX || _activeDragTarget == HDCVLinePlotDragTargetNone) {
        return;
    }
    [self.delegate linePlotView:self
                  didDragXValue:[self clampedXValueForPoint:point]
                          yValue:[self clampedYValueForPoint:point]
                          target:_activeDragTarget];
}

- (void)mouseDown:(NSEvent *)event
{
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    [self.window makeFirstResponder:self];
    if (event.clickCount >= 2) {
        NSRect editorRect = NSZeroRect;
        HDCVAxisEditTarget target = [self axisEditTargetForPoint:point editorRect:&editorRect];
        if (target != HDCVAxisEditTargetNone) {
            [self beginAxisEditingTarget:target rect:editorRect];
            return;
        }
    }
    _activeDragTarget = [self dragTargetForPoint:point];
    if (_activeDragTarget != HDCVLinePlotDragTargetNone) {
        [NSCursor.closedHandCursor set];
        return;
    }
    if (self.viewNavigationEnabled && [self pointIsInPlotRect:point]) {
        _activePanDrag = YES;
        _panStartPoint = point;
        _panStartXMin = self.xMin;
        _panStartXMax = self.xMax;
        _panStartYMin = self.yMin;
        _panStartYMax = self.yMax;
        [NSCursor.closedHandCursor set];
    }
}

- (void)mouseDragged:(NSEvent *)event
{
    if (_activeDragTarget != HDCVLinePlotDragTargetNone) {
        [NSCursor.closedHandCursor set];
        [self dispatchSelectionForEvent:event];
        return;
    }
    if (_activePanDrag) {
        NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
        [NSCursor.closedHandCursor set];
        [self dispatchPanFromPoint:point];
        return;
    }
}

- (void)mouseUp:(NSEvent *)event
{
    (void)event;
    _activeDragTarget = HDCVLinePlotDragTargetNone;
    _activePanDrag = NO;
}

- (void)scrollWheel:(NSEvent *)event
{
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    double deltaY = event.scrollingDeltaY;
    NSEventModifierFlags modifiers = event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;

    if (!self.viewNavigationEnabled || ![self pointIsInPlotRect:point]) {
        [super scrollWheel:event];
        return;
    }

    if ((modifiers & (NSEventModifierFlagOption | NSEventModifierFlagCommand)) != 0U) {
        [self finishAxisEditing];
        if (!event.hasPreciseScrollingDeltas) {
            deltaY *= 8.0;
        }
        double zoomFactor = exp(-deltaY * 0.018);
        [self dispatchZoomWithFactor:zoomFactor aroundPoint:point];
    } else {
        [super scrollWheel:event];
    }
}

- (void)magnifyWithEvent:(NSEvent *)event
{
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    if (!self.viewNavigationEnabled) {
        [super magnifyWithEvent:event];
        return;
    }
    [self finishAxisEditing];
    [self dispatchZoomWithFactor:exp(-event.magnification) aroundPoint:point];
}

- (void)smartMagnifyWithEvent:(NSEvent *)event
{
    (void)event;
    if (!self.viewNavigationEnabled) {
        [super smartMagnifyWithEvent:event];
        return;
    }
    [self.delegate linePlotViewDidRequestResetView:self];
}

@end

@implementation HDCVWaveformProgramView

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self != nil) {
        _rows = @[];
        _summaryText = @"No waveform loaded";
        self.wantsLayer = YES;
        self.layer.backgroundColor = NSColor.clearColor.CGColor;
    }
    return self;
}

- (BOOL)isFlipped
{
    return YES;
}

- (void)setRows:(NSArray<NSDictionary<NSString *,NSString *> *> *)rows
{
    _rows = [rows copy];
    [self invalidateIntrinsicContentSize];
    [self setNeedsDisplay:YES];
}

- (void)setSummaryText:(NSString *)summaryText
{
    _summaryText = [summaryText copy];
    [self setNeedsDisplay:YES];
}

- (CGFloat)preferredContentHeight
{
    return 54.0 + (CGFloat)MAX(self.rows.count, HDCVWaveformProgramVoltageRows) * 24.0 + 12.0;
}

- (NSSize)intrinsicContentSize
{
    return NSMakeSize(NSViewNoIntrinsicMetric, [self preferredContentHeight]);
}

- (NSDictionary<NSAttributedStringKey, id> *)textAttributesWithColor:(NSColor *)color size:(CGFloat)size weight:(NSFontWeight)weight
{
    return @{
        NSFontAttributeName: [NSFont systemFontOfSize:size weight:weight],
        NSForegroundColorAttributeName: color
    };
}

- (void)drawRect:(NSRect)dirtyRect
{
    (void)dirtyRect;
    NSRect bounds = self.bounds;
    CGFloat width = bounds.size.width;
    CGFloat titleY = 4.0;
    CGFloat headerY = 34.0;
    CGFloat rowY = 54.0;
    CGFloat rowHeight = 24.0;
    CGFloat voltageX = 12.0;
    CGFloat timeX = MAX(118.0, width * 0.34);
    CGFloat rateX = MAX(222.0, width * 0.64);
    NSDictionary *titleAttrs = [self textAttributesWithColor:NSColor.blackColor size:12.0 weight:NSFontWeightSemibold];
    NSDictionary *summaryAttrs = [self textAttributesWithColor:HDCVMutedText() size:9.5 weight:NSFontWeightRegular];
    NSDictionary *headerAttrs = [self textAttributesWithColor:HDCVMutedText() size:9.0 weight:NSFontWeightSemibold];
    NSDictionary *cellAttrs = @{
        NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:10.5 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName: [NSColor colorWithWhite:0.13 alpha:1.0]
    };
    NSDictionary *mutedCellAttrs = @{
        NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:10.5 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName: [NSColor colorWithWhite:0.66 alpha:1.0]
    };

    [NSColor.whiteColor setFill];
    NSRectFill(bounds);

    [@"Waveform Program" drawAtPoint:NSMakePoint(voltageX, titleY) withAttributes:titleAttrs];
    if (self.summaryText.length > 0U) {
        [self.summaryText drawAtPoint:NSMakePoint(voltageX, titleY + 17.0) withAttributes:summaryAttrs];
    }

    [@"Voltage (V)" drawAtPoint:NSMakePoint(voltageX, headerY) withAttributes:headerAttrs];
    [@"Time (ms)" drawAtPoint:NSMakePoint(timeX, headerY) withAttributes:headerAttrs];
    [@"Rate (V/s)" drawAtPoint:NSMakePoint(rateX, headerY) withAttributes:headerAttrs];

    [HDCVSoftGridColor() setStroke];
    NSBezierPath *divider = [NSBezierPath bezierPath];
    [divider moveToPoint:NSMakePoint(voltageX, headerY + 17.0)];
    [divider lineToPoint:NSMakePoint(MAX(voltageX, width - 10.0), headerY + 17.0)];
    divider.lineWidth = 0.7;
    [divider stroke];

    if (self.rows.count == 0U) {
        [@"-" drawAtPoint:NSMakePoint(voltageX, rowY) withAttributes:mutedCellAttrs];
        return;
    }

    for (NSUInteger rowIndex = 0U; rowIndex < self.rows.count; ++rowIndex) {
        CGFloat y = rowY + ((CGFloat)rowIndex * rowHeight);
        NSDictionary<NSString *, NSString *> *row = self.rows[rowIndex];
        BOOL active = row[@"active"] == nil || row[@"active"].boolValue;
        NSDictionary *attributes = active ? cellAttrs : mutedCellAttrs;
        if (y > NSMaxY(bounds)) {
            break;
        }
        if ((rowIndex % 2U) == 0U) {
            [[NSColor colorWithWhite:(active ? 0.965 : 0.982) alpha:1.0] setFill];
            NSRectFill(NSMakeRect(6.0, y - 2.0, MAX(0.0, width - 12.0), rowHeight));
        } else if (!active) {
            [[NSColor colorWithWhite:0.988 alpha:1.0] setFill];
            NSRectFill(NSMakeRect(6.0, y - 2.0, MAX(0.0, width - 12.0), rowHeight));
        }

        NSString *voltageText = row[@"voltage"] != nil ? row[@"voltage"] : @"";
        NSString *timeText = row[@"time"] != nil ? row[@"time"] : @"";
        NSString *rateText = row[@"rate"] != nil ? row[@"rate"] : @"";
        [voltageText drawAtPoint:NSMakePoint(voltageX, y + 3.0) withAttributes:attributes];
        [timeText drawAtPoint:NSMakePoint(timeX, y + 3.0) withAttributes:attributes];
        [rateText drawAtPoint:NSMakePoint(rateX, y + 3.0) withAttributes:attributes];
    }
}

@end

@implementation HDCVLoadedFile {
    hdcv_reader _reader;
    BOOL _isOpen;
    NSData *_voltageData;
    NSData *_waveformData;
    NSData *_overviewData;
    uint32_t _overviewColumnCount;
    uint32_t _waveformPointCount;
    uint32_t _waveformFullPointCount;
    double _waveformCycleDurationSeconds;
    double _waveformFullDurationSeconds;
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
    _waveformPointCount = _reader.layout.points_per_scan;
    _waveformFullPointCount = _reader.layout.waveform_full_points;
    _waveformCycleDurationSeconds = (_waveformPointCount > 0U)
        ? (double)(_waveformPointCount - 1U) / _reader.layout.sample_rate_hz
        : 0.0;
    _waveformFullDurationSeconds = (_waveformFullPointCount > 0U && _reader.layout.sample_rate_hz > 0.0)
        ? (double)_waveformFullPointCount / _reader.layout.sample_rate_hz
        : _waveformCycleDurationSeconds;
    _waveformData = _voltageData;

    {
        uint32_t overviewColumns = (uint32_t)MAX((NSUInteger)256U, MIN(maxOverviewColumns, (NSUInteger)2048U));
        NSMutableData *fullOverviewBuffer = [NSMutableData dataWithLength:(NSUInteger)_reader.layout.points_per_scan * (NSUInteger)overviewColumns * sizeof(float)];
        hdcv_overview_result overviewResult;
        if (!hdcv_analysis_build_overview(
                &_reader,
                overviewColumns,
                fullOverviewBuffer.mutableBytes,
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
        fullOverviewBuffer.length = (NSUInteger)_reader.layout.points_per_scan * (NSUInteger)_overviewColumnCount * sizeof(float);
        _overviewMinValue = overviewResult.min_value;
        _overviewMaxValue = overviewResult.max_value;
        _overviewData = [fullOverviewBuffer copy];
    }

    return self;
}

- (void)dealloc
{
    if (_isOpen) {
        hdcv_reader_close(&_reader);
        _isOpen = NO;
    }
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
- (uint32_t)phasePeriod { return MAX(_reader.layout.waveform_count, 1U); }
- (uint32_t)runCount { return _reader.layout.run_count; }
- (uint32_t)scansPerRun { return _reader.layout.scans_per_run; }
- (BOOL)hasExperimentTiming { return _reader.layout.has_experiment_timing != 0; }
- (double)runDurationSeconds { return _reader.layout.run_duration_s; }
- (double)delayBetweenRunsSeconds { return _reader.layout.delay_between_runs_s; }
- (uint32_t)waveformPointCount { return _waveformPointCount; }
- (uint32_t)waveformFullPointCount { return _waveformFullPointCount; }
- (double)waveformCycleDurationSeconds { return _waveformCycleDurationSeconds; }
- (double)waveformFullDurationSeconds { return _waveformFullDurationSeconds; }
- (NSData *)voltageData { return _voltageData; }
- (NSData *)waveformData { return _waveformData; }
- (NSData *)overviewData { return _overviewData; }

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
	    HDCVLinePlotView *_waveformPlotView;
	    HDCVWaveformProgramView *_waveformProgramView;
	    NSScrollView *_waveformProgramScrollView;
	    NSTextField *_heroTitleLabel;
	    NSTextField *_heroStatusLabel;
	    NSTextField *_fileLabel;
	    NSTextField *_heatmapScanField;
	    NSTextField *_heatmapPointField;
	    NSTextField *_heatmapBackgroundField;
	    NSTextField *_timeScanField;
	    NSTextField *_timeBackgroundField;
	    NSTextField *_cvPointField;
	    NSTextField *_backgroundModeLabel;
	    NSTextField *_bandpassFilterLabel;
	    HDCVSwitchControl *_backgroundSubtractSwitch;
	    HDCVSwitchControl *_bandpassFilterSwitch;
	    NSButton *_useSelectedAsBackgroundButton;
	    NSButton *_timeResetViewButton;
	    NSButton *_cvResetViewButton;
	    NSButton *_exportButton;
	    NSProgressIndicator *_progressIndicator;
	    HDCVLoadedFile *_loadedFile;
    NSMutableData *_selectedRawScanData;
    NSMutableData *_backgroundScanData;
    NSMutableData *_selectedPhaseBackgroundScanData;
    NSMutableData *_displayScanData;
    NSMutableData *_displayCVScanData;
    NSMutableData *_rawPointTraceData;
    NSMutableData *_displayPointTraceData;
    float _displayScanMin;
    float _displayScanMax;
    float _displayCVScanMin;
    float _displayCVScanMax;
    float _displayTraceMin;
    float _displayTraceMax;
    NSUInteger _selectedScanIndex;
	    NSUInteger _selectedPointIndex;
	    NSUInteger _backgroundScanIndex;
	    NSUInteger _activePhaseIndex;
	    BOOL _backgroundSubtractEnabled;
	    BOOL _bandpassFilterEnabled;
	    BOOL _exportInProgress;
	    HDCVExportOptions _lastExportOptions;
	    BOOL _heatmapXManual;
	    BOOL _heatmapYManual;
	    BOOL _heatmapColorManual;
	    BOOL _timeXManual;
	    BOOL _timeYManual;
	    BOOL _cvXManual;
	    BOOL _cvYManual;
	    BOOL _waveformXManual;
	    BOOL _waveformYManual;
	    double _heatmapXMinManual;
	    double _heatmapXMaxManual;
	    double _heatmapYMinManual;
	    double _heatmapYMaxManual;
	    double _heatmapColorMinManual;
	    double _heatmapColorMaxManual;
	    double _timeXMinManual;
	    double _timeXMaxManual;
	    double _timeYMinManual;
	    double _timeYMaxManual;
	    double _cvXMinManual;
	    double _cvXMaxManual;
	    double _cvYMinManual;
	    double _cvYMaxManual;
	    double _waveformXMinManual;
	    double _waveformXMaxManual;
	    double _waveformYMinManual;
	    double _waveformYMaxManual;
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
        _activePhaseIndex = 0U;
        _backgroundSubtractEnabled = NO;
        _bandpassFilterEnabled = NO;
        _lastExportOptions = HDCVExportOptionColorPlot | HDCVExportOptionTimePlot | HDCVExportOptionCVPlot;
        id storedExportOptions = [NSUserDefaults.standardUserDefaults objectForKey:HDCVExportOptionsDefaultsKey];
        if ([storedExportOptions isKindOfClass:NSNumber.class]) {
            HDCVExportOptions storedOptions = (HDCVExportOptions)[storedExportOptions unsignedIntegerValue];
            HDCVExportOptions supportedOptions = HDCVExportOptionColorPlot |
                HDCVExportOptionTimePlot |
                HDCVExportOptionCVPlot |
                HDCVExportOptionBackgroundCVPlot;
            if ((storedOptions & supportedOptions) != 0U) {
                _lastExportOptions = storedOptions & supportedOptions;
            }
        }
    }
    return self;
}

- (void)setInitialPathFromArguments:(NSArray<NSString *> *)arguments
{
    if (arguments.count > 1U) {
        _pendingOpenPath = arguments[1];
    }
}

- (void)openFilePathFromSystem:(NSString *)path
{
    if (path.length == 0U) {
        return;
    }
    if (_window == nil) {
        _pendingOpenPath = path;
        return;
    }
    [self loadFileAtPath:path];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    (void)notification;
    [self buildMainMenu];
    [self buildWindow];
    [_window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];

    if (_pendingOpenPath != nil) {
        [self loadFileAtPath:_pendingOpenPath];
    } else {
        _heroStatusLabel.stringValue = @"Open or drag an HDCV FSCV file into the window to begin.";
    }
}

- (BOOL)application:(NSApplication *)sender openFile:(NSString *)filename
{
    (void)sender;
    [self openFilePathFromSystem:filename];
    return YES;
}

- (void)application:(NSApplication *)sender openFiles:(NSArray<NSString *> *)filenames
{
    (void)sender;
    if (filenames.count == 0U) {
        [NSApp replyToOpenOrPrint:NSApplicationDelegateReplyFailure];
        return;
    }
    [self openFilePathFromSystem:filenames.firstObject];
    [NSApp replyToOpenOrPrint:NSApplicationDelegateReplySuccess];
}

- (void)application:(NSApplication *)sender openURLs:(NSArray<NSURL *> *)urls
{
    (void)sender;
    for (NSURL *url in urls) {
        if (url.isFileURL) {
            [self openFilePathFromSystem:url.path];
            return;
        }
    }
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
    (void)sender;
    return YES;
}

- (NSString *)commandLineToolInstallDestination
{
    NSFileManager *fileManager = NSFileManager.defaultManager;
    if ([fileManager isWritableFileAtPath:@"/usr/local/bin"]) {
        return @"/usr/local/bin/hdcv";
    }
    if ([fileManager isWritableFileAtPath:@"/opt/homebrew/bin"]) {
        return @"/opt/homebrew/bin/hdcv";
    }
    return @"/usr/local/bin/hdcv";
}

- (NSString *)bundledCommandLineToolPath
{
    NSString *resourcePath = NSBundle.mainBundle.resourcePath;
    if (resourcePath.length > 0U) {
        NSString *bundledPath = [resourcePath stringByAppendingPathComponent:@"bin/hdcv"];
        if ([NSFileManager.defaultManager isExecutableFileAtPath:bundledPath]) {
            return bundledPath;
        }
    }

    NSString *executablePath = NSBundle.mainBundle.executablePath;
    NSString *buildPath = [executablePath.stringByDeletingLastPathComponent stringByAppendingPathComponent:@"hdcv"];
    if ([NSFileManager.defaultManager isExecutableFileAtPath:buildPath]) {
        return buildPath;
    }
    return nil;
}

- (void)showCommandLineToolAlertWithTitle:(NSString *)title message:(NSString *)message
{
    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleInformational;
    alert.messageText = title;
    alert.informativeText = message;
    [alert beginSheetModalForWindow:_window completionHandler:nil];
}

- (void)installCommandLineTool:(id)sender
{
    (void)sender;
    NSString *sourcePath = [self bundledCommandLineToolPath];
    NSString *destinationPath = [self commandLineToolInstallDestination];
    NSFileManager *fileManager = NSFileManager.defaultManager;
    NSError *error = nil;

    if (sourcePath.length == 0U) {
        [self showCommandLineToolAlertWithTitle:@"Could not find hdcv"
                                        message:@"The command line tool is not embedded in this app bundle or adjacent to this debug build."];
        return;
    }

    NSString *destinationDirectory = destinationPath.stringByDeletingLastPathComponent;
    if (![fileManager createDirectoryAtPath:destinationDirectory withIntermediateDirectories:YES attributes:nil error:&error]) {
        NSString *command = [NSString stringWithFormat:@"sudo mkdir -p \"%@\" && sudo ln -sf \"%@\" \"%@\"", destinationDirectory, sourcePath, destinationPath];
        [self showCommandLineToolAlertWithTitle:@"Install needs permission"
                                        message:[NSString stringWithFormat:@"Could not create %@.\n\nRun this in Terminal:\n%@", destinationDirectory, command]];
        return;
    }

    NSString *existingLinkDestination = [fileManager destinationOfSymbolicLinkAtPath:destinationPath error:nil];
    BOOL destinationExists = [fileManager fileExistsAtPath:destinationPath] || existingLinkDestination != nil;
    if (destinationExists) {
        if (existingLinkDestination == nil) {
            [self showCommandLineToolAlertWithTitle:@"Cannot replace existing file"
                                            message:[NSString stringWithFormat:@"%@ already exists and is not a symlink. Move it first, then install again.", destinationPath]];
            return;
        }
        if (![fileManager removeItemAtPath:destinationPath error:&error]) {
            NSString *command = [NSString stringWithFormat:@"sudo ln -sf \"%@\" \"%@\"", sourcePath, destinationPath];
            [self showCommandLineToolAlertWithTitle:@"Install needs permission"
                                            message:[NSString stringWithFormat:@"Could not replace %@.\n\nRun this in Terminal:\n%@", destinationPath, command]];
            return;
        }
    }

    if (![fileManager createSymbolicLinkAtPath:destinationPath withDestinationPath:sourcePath error:&error]) {
        NSString *command = [NSString stringWithFormat:@"sudo ln -sf \"%@\" \"%@\"", sourcePath, destinationPath];
        [self showCommandLineToolAlertWithTitle:@"Install needs permission"
                                        message:[NSString stringWithFormat:@"Could not install %@.\n\nRun this in Terminal:\n%@", destinationPath, command]];
        return;
    }

    [self showCommandLineToolAlertWithTitle:@"hdcv command installed"
                                    message:[NSString stringWithFormat:@"You can now run:\n\nhdcv file.hdcv\nhdcv file.hdcv --cv 100,200,300 --out exports\n\nInstalled symlink:\n%@ -> %@", destinationPath, sourcePath]];
}

- (void)uninstallCommandLineTool:(id)sender
{
    (void)sender;
    NSString *destinationPath = [self commandLineToolInstallDestination];
    NSFileManager *fileManager = NSFileManager.defaultManager;
    NSError *error = nil;
    NSString *existingLinkDestination = [fileManager destinationOfSymbolicLinkAtPath:destinationPath error:nil];
    BOOL destinationExists = [fileManager fileExistsAtPath:destinationPath] || existingLinkDestination != nil;

    if (!destinationExists) {
        [self showCommandLineToolAlertWithTitle:@"hdcv command is not installed"
                                        message:[NSString stringWithFormat:@"%@ does not exist.", destinationPath]];
        return;
    }
    if (existingLinkDestination == nil) {
        [self showCommandLineToolAlertWithTitle:@"Cannot remove existing file"
                                        message:[NSString stringWithFormat:@"%@ exists and is not a symlink, so HDCV Viewer did not remove it.", destinationPath]];
        return;
    }
    if (![fileManager removeItemAtPath:destinationPath error:&error]) {
        NSString *command = [NSString stringWithFormat:@"sudo rm \"%@\"", destinationPath];
        [self showCommandLineToolAlertWithTitle:@"Uninstall needs permission"
                                        message:[NSString stringWithFormat:@"Could not remove %@.\n\nRun this in Terminal:\n%@", destinationPath, command]];
        return;
    }
    [self showCommandLineToolAlertWithTitle:@"hdcv command removed"
                                    message:[NSString stringWithFormat:@"Removed %@.", destinationPath]];
}

- (void)buildMainMenu
{
    NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@""];
    NSMenuItem *appItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"HDCV Viewer"];
    NSMenuItem *fileItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
    NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];

    [mainMenu addItem:appItem];
    appItem.submenu = appMenu;
    [appMenu addItemWithTitle:@"About HDCV Viewer" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
    [appMenu addItem:NSMenuItem.separatorItem];
    NSMenuItem *installItem = [appMenu addItemWithTitle:@"Install hdcv Command in PATH…" action:@selector(installCommandLineTool:) keyEquivalent:@""];
    installItem.target = self;
    NSMenuItem *uninstallItem = [appMenu addItemWithTitle:@"Uninstall hdcv Command…" action:@selector(uninstallCommandLineTool:) keyEquivalent:@""];
    uninstallItem.target = self;
    [appMenu addItem:NSMenuItem.separatorItem];
    [appMenu addItemWithTitle:@"Quit HDCV Viewer" action:@selector(terminate:) keyEquivalent:@"q"];

    [mainMenu addItem:fileItem];
    fileItem.submenu = fileMenu;
    NSMenuItem *openItem = [fileMenu addItemWithTitle:@"Open…" action:@selector(openDocument:) keyEquivalent:@"o"];
    openItem.target = self;
    NSMenuItem *exportItem = [fileMenu addItemWithTitle:@"Export Data…" action:@selector(exportData:) keyEquivalent:@"e"];
    exportItem.target = self;
    exportItem.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;

    NSApp.mainMenu = mainMenu;
}

- (NSTextField *)compactInputFieldWithAction:(SEL)action width:(CGFloat)width
{
    NSTextField *field = [[NSTextField alloc] initWithFrame:NSZeroRect];
    field.translatesAutoresizingMaskIntoConstraints = NO;
    field.font = [NSFont monospacedDigitSystemFontOfSize:11.0 weight:NSFontWeightMedium];
    field.alignment = NSTextAlignmentRight;
    field.bezelStyle = NSTextFieldRoundedBezel;
    field.controlSize = NSControlSizeSmall;
    field.target = self;
    field.action = action;
    field.delegate = self;
    field.enabled = NO;
    [field.widthAnchor constraintEqualToConstant:width].active = YES;
    return field;
}

- (NSStackView *)controlPairWithLabel:(NSString *)label field:(NSTextField *)field
{
    NSTextField *textLabel = HDCVLabel(label, [NSFont systemFontOfSize:10.0 weight:NSFontWeightSemibold], HDCVMutedText());
    textLabel.alignment = NSTextAlignmentRight;
    NSStackView *pair = [[NSStackView alloc] init];
    pair.translatesAutoresizingMaskIntoConstraints = NO;
    pair.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    pair.alignment = NSLayoutAttributeCenterY;
    pair.spacing = 4.0;
    [pair addArrangedSubview:textLabel];
    [pair addArrangedSubview:field];
    return pair;
}

- (NSStackView *)compactControlsStack
{
    NSStackView *stack = [[NSStackView alloc] init];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    stack.alignment = NSLayoutAttributeCenterY;
    stack.spacing = 8.0;
    return stack;
}

- (NSButton *)smallActionButtonWithTitle:(NSString *)title action:(SEL)action
{
    NSButton *button = [NSButton buttonWithTitle:title target:self action:action];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.bezelStyle = NSBezelStyleRounded;
    button.controlSize = NSControlSizeSmall;
    button.font = [NSFont systemFontOfSize:11.0 weight:NSFontWeightSemibold];
    button.enabled = NO;
    return button;
}

- (void)styleButton:(NSButton *)button
              title:(NSString *)title
          fillColor:(NSColor *)fillColor
          textColor:(NSColor *)textColor
               size:(CGFloat)fontSize
{
    NSDictionary<NSAttributedStringKey, id> *attributes = @{
        NSFontAttributeName: [NSFont systemFontOfSize:fontSize weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName: textColor
    };
    NSAttributedString *attributedTitle = [[NSAttributedString alloc] initWithString:title attributes:attributes];
    button.title = title;
    button.font = attributes[NSFontAttributeName];
    button.attributedTitle = attributedTitle;
    button.attributedAlternateTitle = attributedTitle;
    if (@available(macOS 11.0, *)) {
        button.bezelColor = fillColor;
        button.contentTintColor = textColor;
    }
}

- (void)styleResetButton:(NSButton *)button
{
    [self styleButton:button
                title:@"Reset"
            fillColor:[NSColor colorWithRed:0.86 green:0.93 blue:1.0 alpha:1.0]
            textColor:HDCVAccentBlue()
                 size:10.5];
    [button.widthAnchor constraintGreaterThanOrEqualToConstant:58.0].active = YES;
}

- (void)setInputControlsEnabled:(BOOL)enabled
{
    for (NSTextField *field in @[
        _heatmapScanField, _heatmapPointField, _heatmapBackgroundField,
        _timeScanField, _timeBackgroundField, _cvPointField
    ]) {
        field.enabled = enabled;
    }
    _backgroundSubtractSwitch.enabled = enabled;
    _bandpassFilterSwitch.enabled = enabled;
    _useSelectedAsBackgroundButton.enabled = enabled;
    _timeResetViewButton.enabled = enabled;
    _cvResetViewButton.enabled = enabled;
    _exportButton.enabled = enabled && !_exportInProgress && _loadedFile != nil;
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
    [self styleButton:openButton
                title:@"Import FSCV File"
            fillColor:NSColor.whiteColor
            textColor:HDCVHeroColor()
                 size:13.0];

    _exportButton = [NSButton buttonWithTitle:@"Export Data" target:self action:@selector(exportData:)];
    _exportButton.translatesAutoresizingMaskIntoConstraints = NO;
    _exportButton.bezelStyle = NSBezelStyleRounded;
    _exportButton.enabled = NO;
    [self styleButton:_exportButton
                title:@"Export Data"
            fillColor:[NSColor colorWithRed:0.68 green:0.93 blue:0.88 alpha:1.0]
            textColor:HDCVHeroColor()
                 size:13.0];

    NSStackView *heroActions = [[NSStackView alloc] init];
    heroActions.translatesAutoresizingMaskIntoConstraints = NO;
    heroActions.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    heroActions.alignment = NSLayoutAttributeCenterY;
    heroActions.spacing = 10.0;
    [heroActions addArrangedSubview:openButton];
    [heroActions addArrangedSubview:_exportButton];
    [heroPanel addSubview:heroActions];

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

    [NSLayoutConstraint activateConstraints:@[
        [_heroTitleLabel.leadingAnchor constraintEqualToAnchor:heroPanel.leadingAnchor constant:18.0],
        [_heroTitleLabel.topAnchor constraintEqualToAnchor:heroPanel.topAnchor constant:14.0],
        [_heroStatusLabel.leadingAnchor constraintEqualToAnchor:_heroTitleLabel.leadingAnchor],
        [_heroStatusLabel.topAnchor constraintEqualToAnchor:_heroTitleLabel.bottomAnchor constant:6.0],
        [_heroStatusLabel.trailingAnchor constraintLessThanOrEqualToAnchor:heroActions.leadingAnchor constant:-16.0],
        [_fileLabel.leadingAnchor constraintEqualToAnchor:_heroTitleLabel.leadingAnchor],
        [_fileLabel.topAnchor constraintEqualToAnchor:_heroStatusLabel.bottomAnchor constant:8.0],
        [heroActions.trailingAnchor constraintEqualToAnchor:heroPanel.trailingAnchor constant:-18.0],
        [heroActions.topAnchor constraintEqualToAnchor:heroPanel.topAnchor constant:18.0],
        [_progressIndicator.trailingAnchor constraintEqualToAnchor:heroActions.leadingAnchor constant:-14.0],
        [_progressIndicator.centerYAnchor constraintEqualToAnchor:heroActions.centerYAnchor],
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

    _heatmapBackgroundField = [self compactInputFieldWithAction:@selector(selectionFieldChanged:) width:68.0];
    _heatmapScanField = [self compactInputFieldWithAction:@selector(selectionFieldChanged:) width:68.0];
    _heatmapPointField = [self compactInputFieldWithAction:@selector(selectionFieldChanged:) width:68.0];
    _backgroundSubtractSwitch = [[HDCVSwitchControl alloc] initWithFrame:NSZeroRect];
    _backgroundSubtractSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    _backgroundSubtractSwitch.target = self;
    _backgroundSubtractSwitch.action = @selector(backgroundSubtractToggled:);
    [_backgroundSubtractSwitch.widthAnchor constraintEqualToConstant:48.0].active = YES;
    [_backgroundSubtractSwitch.heightAnchor constraintEqualToConstant:28.0].active = YES;
    _backgroundModeLabel = HDCVLabel(@"BG subtract", [NSFont systemFontOfSize:10.0 weight:NSFontWeightSemibold], HDCVMutedText());
    _useSelectedAsBackgroundButton = [self smallActionButtonWithTitle:@"Set BG = Scan" action:@selector(useSelectedScanAsBackground:)];

    NSStackView *heatmapControls = [self compactControlsStack];
    [heatmapControls addArrangedSubview:[self controlPairWithLabel:@"BG s" field:_heatmapBackgroundField]];
    [heatmapControls addArrangedSubview:[self controlPairWithLabel:@"Time s" field:_heatmapScanField]];
    [heatmapControls addArrangedSubview:[self controlPairWithLabel:@"Volt V" field:_heatmapPointField]];
    [heatmapControls addArrangedSubview:_backgroundModeLabel];
    [heatmapControls addArrangedSubview:_backgroundSubtractSwitch];
    [heatmapControls addArrangedSubview:_useSelectedAsBackgroundButton];
    [heatmapPanel addSubview:heatmapControls];

    [NSLayoutConstraint activateConstraints:@[
        [heatmapControls.trailingAnchor constraintEqualToAnchor:heatmapPanel.trailingAnchor constant:-88.0],
        [heatmapControls.topAnchor constraintEqualToAnchor:heatmapPanel.topAnchor constant:14.0],
        [heatmapControls.leadingAnchor constraintGreaterThanOrEqualToAnchor:heatmapPanel.leadingAnchor constant:170.0],
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
    _timePlotView.viewNavigationEnabled = YES;
    _timePlotView.titleText = @"I-t Plot";
    _timePlotView.xLabelText = @"Sequence Time (s)";
    _timePlotView.yLabelText = @"Current (nA)";
    _timePlotView.xTickFormat = @"%.1f";
    _timePlotView.yTickFormat = @"%.0f";
    _timePlotView.strokeColor = HDCVAccentBlue();
    [timePanel addSubview:_timePlotView];

    _cvPlotView = [[HDCVLinePlotView alloc] initWithFrame:NSZeroRect];
    _cvPlotView.translatesAutoresizingMaskIntoConstraints = NO;
    _cvPlotView.dataSource = self;
    _cvPlotView.delegate = self;
    _cvPlotView.interactionMode = HDCVLinePlotInteractionModeSelectX;
    _cvPlotView.viewNavigationEnabled = YES;
    _cvPlotView.titleText = @"CV Plot";
    _cvPlotView.xLabelText = @"Voltage (V)";
    _cvPlotView.yLabelText = @"Current (nA)";
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

    _timeBackgroundField = [self compactInputFieldWithAction:@selector(selectionFieldChanged:) width:58.0];
    _timeScanField = [self compactInputFieldWithAction:@selector(selectionFieldChanged:) width:58.0];
    _bandpassFilterSwitch = [[HDCVSwitchControl alloc] initWithFrame:NSZeroRect];
    _bandpassFilterSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    _bandpassFilterSwitch.target = self;
    _bandpassFilterSwitch.action = @selector(bandpassFilterToggled:);
    [_bandpassFilterSwitch.widthAnchor constraintEqualToConstant:48.0].active = YES;
    [_bandpassFilterSwitch.heightAnchor constraintEqualToConstant:28.0].active = YES;
    _bandpassFilterLabel = HDCVLabel(@"BP", [NSFont systemFontOfSize:10.0 weight:NSFontWeightSemibold], HDCVMutedText());
    _timeResetViewButton = [self smallActionButtonWithTitle:@"Reset" action:@selector(resetTimePlotView:)];
    [self styleResetButton:_timeResetViewButton];

    NSStackView *timePrimaryControls = [self compactControlsStack];
    [timePrimaryControls addArrangedSubview:[self controlPairWithLabel:@"BG s" field:_timeBackgroundField]];
    [timePrimaryControls addArrangedSubview:[self controlPairWithLabel:@"Time s" field:_timeScanField]];
    [timePrimaryControls addArrangedSubview:_bandpassFilterLabel];
    [timePrimaryControls addArrangedSubview:_bandpassFilterSwitch];
    [timePrimaryControls addArrangedSubview:_timeResetViewButton];
    [timePanel addSubview:timePrimaryControls];

    _cvPointField = [self compactInputFieldWithAction:@selector(selectionFieldChanged:) width:58.0];
    _cvResetViewButton = [self smallActionButtonWithTitle:@"Reset" action:@selector(resetCVPlotView:)];
    [self styleResetButton:_cvResetViewButton];

    NSStackView *cvPrimaryControls = [self compactControlsStack];
    [cvPrimaryControls addArrangedSubview:[self controlPairWithLabel:@"Volt V" field:_cvPointField]];
    [cvPrimaryControls addArrangedSubview:_cvResetViewButton];
    [cvPanel addSubview:cvPrimaryControls];

    NSLayoutConstraint *timeControlsLeading = [timePrimaryControls.leadingAnchor constraintGreaterThanOrEqualToAnchor:timePanel.leadingAnchor constant:112.0];
    NSLayoutConstraint *cvControlsLeading = [cvPrimaryControls.leadingAnchor constraintGreaterThanOrEqualToAnchor:cvPanel.leadingAnchor constant:112.0];
    timeControlsLeading.priority = NSLayoutPriorityDefaultLow;
    cvControlsLeading.priority = NSLayoutPriorityDefaultLow;

    [NSLayoutConstraint activateConstraints:@[
        [timePrimaryControls.trailingAnchor constraintEqualToAnchor:timePanel.trailingAnchor constant:-32.0],
        [timePrimaryControls.topAnchor constraintEqualToAnchor:timePanel.topAnchor constant:13.0],
        timeControlsLeading,

        [cvPrimaryControls.trailingAnchor constraintEqualToAnchor:cvPanel.trailingAnchor constant:-32.0],
        [cvPrimaryControls.topAnchor constraintEqualToAnchor:cvPanel.topAnchor constant:13.0],
        cvControlsLeading,
    ]];

    NSView *waveformPanel = HDCVPanelContainer();
    [sidebarColumn addArrangedSubview:waveformPanel];
    [waveformPanel.heightAnchor constraintGreaterThanOrEqualToConstant:600.0].active = YES;

    NSStackView *waveformStack = [[NSStackView alloc] init];
    waveformStack.translatesAutoresizingMaskIntoConstraints = NO;
    waveformStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    waveformStack.spacing = 8.0;
    [waveformPanel addSubview:waveformStack];

    _waveformPlotView = [[HDCVLinePlotView alloc] initWithFrame:NSZeroRect];
    _waveformPlotView.translatesAutoresizingMaskIntoConstraints = NO;
    _waveformPlotView.dataSource = self;
    _waveformPlotView.delegate = self;
    _waveformPlotView.interactionMode = HDCVLinePlotInteractionModeSelectX;
    _waveformPlotView.titleText = @"FSCV Waveform";
    _waveformPlotView.subtitleText = @"No file loaded";
    _waveformPlotView.xLabelText = @"Time (ms)";
    _waveformPlotView.yLabelText = @"Voltage (V)";
    _waveformPlotView.xTickFormat = @"%.2f";
    _waveformPlotView.yTickFormat = @"%.2f";
    _waveformPlotView.strokeColor = HDCVAccentTeal();
    [waveformStack addArrangedSubview:_waveformPlotView];

    _waveformProgramView = [[HDCVWaveformProgramView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 360.0, 306.0)];
    _waveformProgramView.autoresizingMask = NSViewWidthSizable;
    _waveformProgramScrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    _waveformProgramScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _waveformProgramScrollView.borderType = NSNoBorder;
    _waveformProgramScrollView.drawsBackground = NO;
    _waveformProgramScrollView.hasVerticalScroller = NO;
    _waveformProgramScrollView.hasHorizontalScroller = NO;
    _waveformProgramScrollView.documentView = _waveformProgramView;
    [waveformStack addArrangedSubview:_waveformProgramScrollView];

    [NSLayoutConstraint activateConstraints:@[
        [waveformStack.leadingAnchor constraintEqualToAnchor:waveformPanel.leadingAnchor constant:8.0],
        [waveformStack.trailingAnchor constraintEqualToAnchor:waveformPanel.trailingAnchor constant:-8.0],
        [waveformStack.topAnchor constraintEqualToAnchor:waveformPanel.topAnchor constant:8.0],
        [waveformStack.bottomAnchor constraintEqualToAnchor:waveformPanel.bottomAnchor constant:-8.0],
        [_waveformPlotView.heightAnchor constraintGreaterThanOrEqualToConstant:254.0],
        [_waveformProgramScrollView.heightAnchor constraintEqualToConstant:306.0],
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

- (void)exportData:(id)sender
{
    (void)sender;
    if (_loadedFile == nil || _exportInProgress) {
        return;
    }

    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleInformational;
    alert.messageText = @"Export FSCV plot data";
    alert.informativeText = @"Exports use the current plot state and active phase. I-t uses the selected voltage; CV uses the selected time; background CV uses the background line.";
    [alert addButtonWithTitle:@"Export"];
    [alert addButtonWithTitle:@"Cancel"];

    NSButton *colorCheck = [NSButton checkboxWithTitle:@"Color plot data (t, I, V)" target:nil action:nil];
    NSButton *timeCheck = [NSButton checkboxWithTitle:@"I-t plot (t, I)" target:nil action:nil];
    NSButton *cvCheck = [NSButton checkboxWithTitle:@"CV plot (V, I)" target:nil action:nil];
    NSButton *backgroundCVCheck = [NSButton checkboxWithTitle:@"Background CV plot (V, I)" target:nil action:nil];
    colorCheck.state = ((_lastExportOptions & HDCVExportOptionColorPlot) != 0U) ? NSControlStateValueOn : NSControlStateValueOff;
    timeCheck.state = ((_lastExportOptions & HDCVExportOptionTimePlot) != 0U) ? NSControlStateValueOn : NSControlStateValueOff;
    cvCheck.state = ((_lastExportOptions & HDCVExportOptionCVPlot) != 0U) ? NSControlStateValueOn : NSControlStateValueOff;
    backgroundCVCheck.state = ((_lastExportOptions & HDCVExportOptionBackgroundCVPlot) != 0U) ? NSControlStateValueOn : NSControlStateValueOff;

    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 330.0, 112.0)];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 8.0;
    [stack addArrangedSubview:colorCheck];
    [stack addArrangedSubview:timeCheck];
    [stack addArrangedSubview:cvCheck];
    [stack addArrangedSubview:backgroundCVCheck];
    alert.accessoryView = stack;

    [alert beginSheetModalForWindow:_window completionHandler:^(NSModalResponse response) {
        if (response != NSAlertFirstButtonReturn) {
            return;
        }

        HDCVExportOptions options = 0U;
        NSUInteger selectedCount = 0U;
        if (colorCheck.state == NSControlStateValueOn) {
            options |= HDCVExportOptionColorPlot;
            selectedCount += 1U;
        }
        if (timeCheck.state == NSControlStateValueOn) {
            options |= HDCVExportOptionTimePlot;
            selectedCount += 1U;
        }
        if (cvCheck.state == NSControlStateValueOn) {
            options |= HDCVExportOptionCVPlot;
            selectedCount += 1U;
        }
        if (backgroundCVCheck.state == NSControlStateValueOn) {
            options |= HDCVExportOptionBackgroundCVPlot;
            selectedCount += 1U;
        }

        if (selectedCount == 0U) {
            NSAlert *emptyAlert = [[NSAlert alloc] init];
            emptyAlert.alertStyle = NSAlertStyleWarning;
            emptyAlert.messageText = @"Choose at least one CSV export";
            [emptyAlert beginSheetModalForWindow:self->_window completionHandler:nil];
            return;
        }
        self->_lastExportOptions = options;
        [NSUserDefaults.standardUserDefaults setInteger:(NSInteger)options forKey:HDCVExportOptionsDefaultsKey];

        NSSavePanel *savePanel = [NSSavePanel savePanel];
        NSString *baseName = self->_pendingOpenPath.lastPathComponent.stringByDeletingPathExtension;
        if (baseName.length == 0U) {
            baseName = @"hdcv_export";
        }
        savePanel.nameFieldStringValue = [NSString stringWithFormat:@"%@_export.csv", baseName];
        savePanel.message = selectedCount > 1U
            ? @"Choose a base filename. The selected plots will be written as separate suffixed CSV files."
            : @"Choose the CSV filename.";
        savePanel.canCreateDirectories = YES;

        [savePanel beginSheetModalForWindow:self->_window completionHandler:^(NSModalResponse saveResponse) {
            if (saveResponse != NSModalResponseOK || savePanel.URL == nil) {
                return;
            }
            [self performExportWithOptions:options baseURL:savePanel.URL singleFile:(selectedCount == 1U)];
        }];
    }];
}

- (void)dropHostView:(HDCVDropHostView *)view didReceiveFilePath:(NSString *)filePath
{
    (void)view;
    [self loadFileAtPath:filePath];
}

- (BOOL)writeTimePlotCSVToURL:(NSURL *)url
                    loadedFile:(HDCVLoadedFile *)loadedFile
                    pointIndex:(NSUInteger)pointIndex
           backgroundScanIndex:(NSUInteger)backgroundScanIndex
    backgroundSubtractEnabled:(BOOL)backgroundSubtractEnabled
         bandpassFilterEnabled:(BOOL)bandpassFilterEnabled
              activePhaseIndex:(NSUInteger)activePhaseIndex
                   phasePeriod:(NSUInteger)phasePeriod
                         error:(NSError **)error
{
    NSUInteger scanCount = loadedFile.scanCount;
    NSMutableData *traceData = [NSMutableData dataWithLength:scanCount * sizeof(float)];
    FILE *file = HDCVOpenCSVFile(url, error);
    if (file == NULL) {
        return NO;
    }

    if (![loadedFile copyPointTraceAtIndex:(uint32_t)pointIndex intoMutableData:traceData min:NULL max:NULL]) {
        fclose(file);
        HDCVSetCSVError(error, url, @"Could not read the selected I-t trace.");
        return NO;
    }

    float *trace = traceData.mutableBytes;
    if (backgroundSubtractEnabled) {
        NSMutableData *sourceTraceData = [NSMutableData dataWithLength:scanCount * sizeof(float)];
        memcpy(sourceTraceData.mutableBytes, trace, scanCount * sizeof(float));
        HDCVApplyPhaseAlignedBackgroundToTrace(
            sourceTraceData.bytes,
            trace,
            scanCount,
            backgroundScanIndex,
            phasePeriod
        );
    }
    if (bandpassFilterEnabled) {
        (void)HDCVApplyButterworthBandpassByPhase(trace, scanCount, phasePeriod, loadedFile.cvfHz);
    }

    fprintf(file, "time_s,current_nA\n");
    NSUInteger firstScan = HDCVFirstPhaseScanInRange(0U, scanCount - 1U, activePhaseIndex, phasePeriod);
    for (NSUInteger scanIndex = firstScan; scanIndex != NSNotFound && scanIndex < scanCount; scanIndex += MAX(phasePeriod, 1U)) {
        fprintf(file, "%.9g,%.9g\n", [loadedFile sequenceTimeSecondsAtScan:scanIndex], (double)trace[scanIndex]);
    }
    return HDCVCloseCSVFile(file, url, error);
}

- (BOOL)writeCVPlotCSVToURL:(NSURL *)url
                 loadedFile:(HDCVLoadedFile *)loadedFile
                  scanIndex:(NSUInteger)scanIndex
        backgroundScanIndex:(NSUInteger)backgroundScanIndex
 backgroundSubtractEnabled:(BOOL)backgroundSubtractEnabled
      bandpassFilterEnabled:(BOOL)bandpassFilterEnabled
           activePhaseIndex:(NSUInteger)activePhaseIndex
                phasePeriod:(NSUInteger)phasePeriod
                      error:(NSError **)error
{
    NSUInteger scanCount = loadedFile.scanCount;
    NSUInteger pointsPerScan = loadedFile.pointsPerScan;
    NSUInteger selectedCenter = HDCVNearestScanIndexForPhase(scanIndex, scanCount, activePhaseIndex, phasePeriod);
    NSUInteger backgroundCenter = HDCVNearestScanIndexForPhase(backgroundScanIndex, scanCount, activePhaseIndex, phasePeriod);
    FILE *file = HDCVOpenCSVFile(url, error);
    if (file == NULL) {
        return NO;
    }

    fprintf(file, "voltage_V,current_nA\n");
    if (backgroundSubtractEnabled && selectedCenter == backgroundCenter) {
        for (NSUInteger pointIndex = 0U; pointIndex < pointsPerScan; ++pointIndex) {
            fprintf(file, "%.9g,0\n", (double)[loadedFile voltageAtPoint:pointIndex]);
        }
        return HDCVCloseCSVFile(file, url, error);
    }

    if (bandpassFilterEnabled) {
        NSMutableData *traceData = [NSMutableData dataWithLength:scanCount * sizeof(float)];
        NSMutableData *sourceTraceData = backgroundSubtractEnabled ? [NSMutableData dataWithLength:scanCount * sizeof(float)] : nil;
        NSMutableData *cvData = [NSMutableData dataWithLength:pointsPerScan * sizeof(float)];
        float *cvValues = cvData.mutableBytes;

        for (NSUInteger pointIndex = 0U; pointIndex < pointsPerScan; ++pointIndex) {
            if (![loadedFile copyPointTraceAtIndex:(uint32_t)pointIndex intoMutableData:traceData min:NULL max:NULL]) {
                fclose(file);
                HDCVSetCSVError(error, url, @"Could not read a waveform-point trace for CV export.");
                return NO;
            }

            float *trace = traceData.mutableBytes;
            if (backgroundSubtractEnabled) {
                memcpy(sourceTraceData.mutableBytes, trace, scanCount * sizeof(float));
                HDCVApplyPhaseAlignedBackgroundToTrace(
                    sourceTraceData.bytes,
                    trace,
                    scanCount,
                    backgroundScanIndex,
                    phasePeriod
                );
            }
            (void)HDCVApplyButterworthBandpassByPhase(trace, scanCount, phasePeriod, loadedFile.cvfHz);
            float current = HDCVAverageTraceInPhaseWindow(
                trace,
                scanCount,
                selectedCenter,
                activePhaseIndex,
                phasePeriod,
                HDCVCVSelectedHalfWindow
            );
            cvValues[pointIndex] = current;
        }
        if (backgroundSubtractEnabled) {
            HDCVApplyBackgroundSubtractedCVDenoise(cvValues, loadedFile.voltageData.bytes, pointsPerScan);
        }
        for (NSUInteger pointIndex = 0U; pointIndex < pointsPerScan; ++pointIndex) {
            fprintf(file, "%.9g,%.9g\n", (double)[loadedFile voltageAtPoint:pointIndex], (double)cvValues[pointIndex]);
        }
    } else {
        NSMutableData *selectedAverageData = [NSMutableData dataWithLength:pointsPerScan * sizeof(float)];
        NSMutableData *backgroundAverageData = [NSMutableData dataWithLength:pointsPerScan * sizeof(float)];
        NSMutableData *cvData = [NSMutableData dataWithLength:pointsPerScan * sizeof(float)];
        NSMutableData *scratchData = [NSMutableData dataWithLength:pointsPerScan * sizeof(float)];
        NSMutableData *sumsData = [NSMutableData dataWithLength:pointsPerScan * sizeof(double)];
        double *sums = sumsData.mutableBytes;
        float *selectedAverage = selectedAverageData.mutableBytes;
        float *backgroundAverage = backgroundAverageData.mutableBytes;
        float *cvValues = cvData.mutableBytes;
        BOOL hasBackgroundAverage = NO;

        BOOL (^copyAverageScan)(NSUInteger, NSUInteger, float *) = ^BOOL(NSUInteger centerScan, NSUInteger halfWindow, float *destination) {
            NSUInteger center = HDCVNearestScanIndexForPhase(centerScan, scanCount, activePhaseIndex, phasePeriod);
            NSInteger start = (NSInteger)center - ((NSInteger)halfWindow * (NSInteger)phasePeriod);
            NSInteger end = (NSInteger)center + ((NSInteger)halfWindow * (NSInteger)phasePeriod);
            NSUInteger usedCount = 0U;
            memset(sums, 0, pointsPerScan * sizeof(double));
            while (start < 0) {
                start += (NSInteger)phasePeriod;
            }
            while (end >= (NSInteger)scanCount) {
                end -= (NSInteger)phasePeriod;
            }
            for (NSInteger localScan = start; localScan <= end; localScan += (NSInteger)phasePeriod) {
                if (localScan < 0 || localScan >= (NSInteger)scanCount) {
                    continue;
                }
                if (![loadedFile copyScanAtIndex:(uint32_t)localScan intoMutableData:scratchData min:NULL max:NULL]) {
                    return NO;
                }
                const float *scratch = scratchData.bytes;
                for (NSUInteger pointIndex = 0U; pointIndex < pointsPerScan; ++pointIndex) {
                    sums[pointIndex] += (double)scratch[pointIndex];
                }
                usedCount += 1U;
            }
            if (usedCount == 0U) {
                if (![loadedFile copyScanAtIndex:(uint32_t)center intoMutableData:scratchData min:NULL max:NULL]) {
                    return NO;
                }
                memcpy(destination, scratchData.bytes, pointsPerScan * sizeof(float));
                return YES;
            }
            double invCount = 1.0 / (double)usedCount;
            for (NSUInteger pointIndex = 0U; pointIndex < pointsPerScan; ++pointIndex) {
                destination[pointIndex] = (float)(sums[pointIndex] * invCount);
            }
            return YES;
        };

        if (!copyAverageScan(scanIndex, HDCVCVSelectedHalfWindow, selectedAverage)) {
            fclose(file);
            HDCVSetCSVError(error, url, @"Could not read the selected CV scan average.");
            return NO;
        }

        if (backgroundSubtractEnabled) {
            if (!copyAverageScan(backgroundCenter, HDCVCVSelectedHalfWindow, backgroundAverage)) {
                fclose(file);
                HDCVSetCSVError(error, url, @"Could not read the phase-aligned background average for CV export.");
                return NO;
            }
            hasBackgroundAverage = YES;
        }

        for (NSUInteger pointIndex = 0U; pointIndex < pointsPerScan; ++pointIndex) {
            double current = (double)selectedAverage[pointIndex] - (hasBackgroundAverage ? (double)backgroundAverage[pointIndex] : 0.0);
            cvValues[pointIndex] = (float)current;
        }
        if (backgroundSubtractEnabled) {
            HDCVApplyBackgroundSubtractedCVDenoise(cvValues, loadedFile.voltageData.bytes, pointsPerScan);
        }
        for (NSUInteger pointIndex = 0U; pointIndex < pointsPerScan; ++pointIndex) {
            fprintf(file, "%.9g,%.9g\n", (double)[loadedFile voltageAtPoint:pointIndex], (double)cvValues[pointIndex]);
        }
    }

    return HDCVCloseCSVFile(file, url, error);
}

- (BOOL)writeColorPlotCSVToURL:(NSURL *)url
                    loadedFile:(HDCVLoadedFile *)loadedFile
                    scanMinIndex:(NSUInteger)scanMinIndex
                    scanMaxIndex:(NSUInteger)scanMaxIndex
                   pointMinIndex:(NSUInteger)pointMinIndex
                   pointMaxIndex:(NSUInteger)pointMaxIndex
            backgroundScanIndex:(NSUInteger)backgroundScanIndex
     backgroundSubtractEnabled:(BOOL)backgroundSubtractEnabled
          bandpassFilterEnabled:(BOOL)bandpassFilterEnabled
               activePhaseIndex:(NSUInteger)activePhaseIndex
                    phasePeriod:(NSUInteger)phasePeriod
                          error:(NSError **)error
{
    NSUInteger scanCount = loadedFile.scanCount;
    NSUInteger pointsPerScan = loadedFile.pointsPerScan;
    NSUInteger exportScanCount = HDCVPhaseSampleCountInRange(scanMinIndex, scanMaxIndex, activePhaseIndex, phasePeriod);
    NSUInteger exportPointCount = pointMaxIndex - pointMinIndex + 1U;
    FILE *file = HDCVOpenCSVFile(url, error);
    if (file == NULL) {
        return NO;
    }

    fprintf(file, "time_s,current_nA,voltage_V\n");
    if (bandpassFilterEnabled) {
        NSMutableData *traceData = [NSMutableData dataWithLength:scanCount * sizeof(float)];
        NSMutableData *sourceTraceData = backgroundSubtractEnabled ? [NSMutableData dataWithLength:scanCount * sizeof(float)] : nil;
        NSMutableData *matrixData = [NSMutableData dataWithLength:exportScanCount * exportPointCount * sizeof(float)];
        float *matrix = matrixData.mutableBytes;

        for (NSUInteger pointIndex = pointMinIndex; pointIndex <= pointMaxIndex; ++pointIndex) {
            if (![loadedFile copyPointTraceAtIndex:(uint32_t)pointIndex intoMutableData:traceData min:NULL max:NULL]) {
                fclose(file);
                HDCVSetCSVError(error, url, @"Could not read a waveform-point trace for color plot export.");
                return NO;
            }

            float *trace = traceData.mutableBytes;
            if (backgroundSubtractEnabled) {
                memcpy(sourceTraceData.mutableBytes, trace, scanCount * sizeof(float));
                HDCVApplyPhaseAlignedBackgroundToTrace(
                    sourceTraceData.bytes,
                    trace,
                    scanCount,
                    backgroundScanIndex,
                    phasePeriod
                );
            }
            (void)HDCVApplyButterworthBandpassByPhase(trace, scanCount, phasePeriod, loadedFile.cvfHz);

            NSUInteger localPoint = pointIndex - pointMinIndex;
            NSUInteger localScan = 0U;
            NSUInteger firstScan = HDCVFirstPhaseScanInRange(scanMinIndex, scanMaxIndex, activePhaseIndex, phasePeriod);
            for (NSUInteger scanIndex = firstScan; scanIndex != NSNotFound && scanIndex <= scanMaxIndex; scanIndex += MAX(phasePeriod, 1U)) {
                matrix[(localScan * exportPointCount) + localPoint] = trace[scanIndex];
                localScan += 1U;
            }
        }

        NSUInteger localScan = 0U;
        NSUInteger firstScan = HDCVFirstPhaseScanInRange(scanMinIndex, scanMaxIndex, activePhaseIndex, phasePeriod);
        for (NSUInteger scanIndex = firstScan; scanIndex != NSNotFound && scanIndex <= scanMaxIndex; scanIndex += MAX(phasePeriod, 1U)) {
            double time = [loadedFile sequenceTimeSecondsAtScan:scanIndex];
            for (NSUInteger pointIndex = pointMinIndex; pointIndex <= pointMaxIndex; ++pointIndex) {
                NSUInteger localPoint = pointIndex - pointMinIndex;
                fprintf(
                    file,
                    "%.9g,%.9g,%.9g\n",
                    time,
                    (double)matrix[(localScan * exportPointCount) + localPoint],
                    (double)[loadedFile voltageAtPoint:pointIndex]
                );
            }
            localScan += 1U;
        }
    } else {
        NSMutableDictionary<NSNumber *, NSData *> *backgroundCache = [NSMutableDictionary dictionary];
        NSMutableData *scanData = [NSMutableData dataWithLength:pointsPerScan * sizeof(float)];

        NSUInteger firstScan = HDCVFirstPhaseScanInRange(scanMinIndex, scanMaxIndex, activePhaseIndex, phasePeriod);
        for (NSUInteger scanIndex = firstScan; scanIndex != NSNotFound && scanIndex <= scanMaxIndex; scanIndex += MAX(phasePeriod, 1U)) {
            if (![loadedFile copyScanAtIndex:(uint32_t)scanIndex intoMutableData:scanData min:NULL max:NULL]) {
                fclose(file);
                HDCVSetCSVError(error, url, @"Could not read a scan for color plot export.");
                return NO;
            }

            const float *background = NULL;
            if (backgroundSubtractEnabled) {
                NSUInteger alignedIndex = HDCVPhaseAlignedBackgroundIndex(backgroundScanIndex, scanIndex, scanCount, phasePeriod);
                NSNumber *key = @(alignedIndex);
                NSData *cachedBackground = backgroundCache[key];
                if (cachedBackground == nil) {
                    NSMutableData *backgroundData = [NSMutableData dataWithLength:pointsPerScan * sizeof(float)];
                    if (![loadedFile copyScanAtIndex:(uint32_t)alignedIndex intoMutableData:backgroundData min:NULL max:NULL]) {
                        fclose(file);
                        HDCVSetCSVError(error, url, @"Could not read a phase-aligned background scan for color plot export.");
                        return NO;
                    }
                    cachedBackground = [backgroundData copy];
                    backgroundCache[key] = cachedBackground;
                }
                background = cachedBackground.bytes;
            }

            const float *scan = scanData.bytes;
            double time = [loadedFile sequenceTimeSecondsAtScan:scanIndex];
            for (NSUInteger pointIndex = pointMinIndex; pointIndex <= pointMaxIndex; ++pointIndex) {
                double current = (double)scan[pointIndex] - ((background != NULL) ? (double)background[pointIndex] : 0.0);
                fprintf(file, "%.9g,%.9g,%.9g\n", time, current, (double)[loadedFile voltageAtPoint:pointIndex]);
            }
        }
    }

    return HDCVCloseCSVFile(file, url, error);
}

- (void)performExportWithOptions:(HDCVExportOptions)options baseURL:(NSURL *)baseURL singleFile:(BOOL)singleFile
{
    HDCVLoadedFile *loadedFile = _loadedFile;
    if (loadedFile == nil) {
        return;
    }

    NSUInteger selectedScanIndex = MIN(_selectedScanIndex, (NSUInteger)loadedFile.scanCount - 1U);
    NSUInteger selectedPointIndex = MIN(_selectedPointIndex, (NSUInteger)loadedFile.pointsPerScan - 1U);
    NSUInteger backgroundScanIndex = MIN(_backgroundScanIndex, (NSUInteger)loadedFile.scanCount - 1U);
    NSUInteger phasePeriod = MAX((NSUInteger)loadedFile.phasePeriod, 1U);
    NSUInteger activePhaseIndex = _activePhaseIndex % phasePeriod;
    BOOL backgroundSubtractEnabled = _backgroundSubtractEnabled;
    BOOL bandpassFilterEnabled = _bandpassFilterEnabled;
    NSUInteger scanMinIndex = MIN(_heatmapView.visibleScanMinIndex, (NSUInteger)loadedFile.scanCount - 1U);
    NSUInteger scanMaxIndex = (_heatmapView.visibleScanMaxIndex == NSNotFound)
        ? (NSUInteger)loadedFile.scanCount - 1U
        : MIN(_heatmapView.visibleScanMaxIndex, (NSUInteger)loadedFile.scanCount - 1U);
    NSUInteger pointMinIndex = MIN(_heatmapView.visiblePointMinIndex, (NSUInteger)loadedFile.pointsPerScan - 1U);
    NSUInteger pointMaxIndex = (_heatmapView.visiblePointMaxIndex == NSNotFound)
        ? (NSUInteger)loadedFile.pointsPerScan - 1U
        : MIN(_heatmapView.visiblePointMaxIndex, (NSUInteger)loadedFile.pointsPerScan - 1U);

    if (scanMaxIndex < scanMinIndex) {
        scanMaxIndex = scanMinIndex;
    }
    if (pointMaxIndex < pointMinIndex) {
        pointMaxIndex = pointMinIndex;
    }

    _exportInProgress = YES;
    _exportButton.enabled = NO;
    _heroStatusLabel.stringValue = @"Exporting CSV data from the current FSCV plot state…";
    [_progressIndicator startAnimation:nil];

    dispatch_async(_workerQueue, ^{
        NSError *error = nil;
        NSMutableArray<NSURL *> *writtenURLs = [NSMutableArray array];

        if ((options & HDCVExportOptionColorPlot) != 0U) {
            NSURL *url = HDCVExportURLForSuffix(baseURL, @"color", singleFile);
            if (![self writeColorPlotCSVToURL:url
                                   loadedFile:loadedFile
                                 scanMinIndex:scanMinIndex
                                 scanMaxIndex:scanMaxIndex
                                pointMinIndex:pointMinIndex
                                pointMaxIndex:pointMaxIndex
                          backgroundScanIndex:backgroundScanIndex
                   backgroundSubtractEnabled:backgroundSubtractEnabled
                        bandpassFilterEnabled:bandpassFilterEnabled
                              activePhaseIndex:activePhaseIndex
                                  phasePeriod:phasePeriod
                                        error:&error]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self finishExportWithError:error writtenURLs:writtenURLs];
                });
                return;
            }
            [writtenURLs addObject:url];
        }

        if ((options & HDCVExportOptionTimePlot) != 0U) {
            NSURL *url = HDCVExportURLForSuffix(baseURL, @"it", singleFile);
            if (![self writeTimePlotCSVToURL:url
                                  loadedFile:loadedFile
                                  pointIndex:selectedPointIndex
                         backgroundScanIndex:backgroundScanIndex
                  backgroundSubtractEnabled:backgroundSubtractEnabled
                       bandpassFilterEnabled:bandpassFilterEnabled
                             activePhaseIndex:activePhaseIndex
                                 phasePeriod:phasePeriod
                                       error:&error]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self finishExportWithError:error writtenURLs:writtenURLs];
                });
                return;
            }
            [writtenURLs addObject:url];
        }

        if ((options & HDCVExportOptionCVPlot) != 0U) {
            NSURL *url = HDCVExportURLForSuffix(baseURL, @"cv", singleFile);
            if (![self writeCVPlotCSVToURL:url
                                loadedFile:loadedFile
                                 scanIndex:selectedScanIndex
                       backgroundScanIndex:backgroundScanIndex
                backgroundSubtractEnabled:backgroundSubtractEnabled
                     bandpassFilterEnabled:bandpassFilterEnabled
                          activePhaseIndex:activePhaseIndex
                               phasePeriod:phasePeriod
                                     error:&error]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self finishExportWithError:error writtenURLs:writtenURLs];
                });
                return;
            }
            [writtenURLs addObject:url];
        }

        if ((options & HDCVExportOptionBackgroundCVPlot) != 0U) {
            NSURL *url = HDCVExportURLForSuffix(baseURL, @"cv_bg", singleFile);
            if (![self writeCVPlotCSVToURL:url
                                loadedFile:loadedFile
                                 scanIndex:backgroundScanIndex
                       backgroundScanIndex:backgroundScanIndex
                backgroundSubtractEnabled:NO
                     bandpassFilterEnabled:bandpassFilterEnabled
                          activePhaseIndex:activePhaseIndex
                               phasePeriod:phasePeriod
                                     error:&error]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self finishExportWithError:error writtenURLs:writtenURLs];
                });
                return;
            }
            [writtenURLs addObject:url];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [self finishExportWithError:nil writtenURLs:writtenURLs];
        });
    });
}

- (void)finishExportWithError:(NSError *)error writtenURLs:(NSArray<NSURL *> *)writtenURLs
{
    _exportInProgress = NO;
    [_progressIndicator stopAnimation:nil];
    [self setInputControlsEnabled:(_loadedFile != nil)];

    if (error != nil) {
        _heroStatusLabel.stringValue = error.localizedDescription;
        NSAlert *alert = [[NSAlert alloc] init];
        alert.alertStyle = NSAlertStyleWarning;
        alert.messageText = @"CSV export failed";
        alert.informativeText = (error.localizedDescription != nil)
            ? error.localizedDescription
            : @"The selected plot data could not be exported.";
        [alert beginSheetModalForWindow:_window completionHandler:nil];
        return;
    }

    NSString *fileList = [[writtenURLs valueForKey:@"lastPathComponent"] componentsJoinedByString:@", "];
    _heroStatusLabel.stringValue = [NSString stringWithFormat:@"Export complete: %@", fileList];
}

- (void)loadFileAtPath:(NSString *)path
{
    _pendingOpenPath = path;
    [self setInputControlsEnabled:NO];
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

    _selectedRawScanData = [NSMutableData dataWithLength:(NSUInteger)loaded.pointsPerScan * sizeof(float)];
    _backgroundScanData = [NSMutableData dataWithLength:(NSUInteger)loaded.pointsPerScan * sizeof(float)];
    _selectedPhaseBackgroundScanData = [NSMutableData dataWithLength:(NSUInteger)loaded.pointsPerScan * sizeof(float)];
    _displayScanData = [NSMutableData dataWithLength:(NSUInteger)loaded.pointsPerScan * sizeof(float)];
    _displayCVScanData = [NSMutableData dataWithLength:(NSUInteger)loaded.pointsPerScan * sizeof(float)];
    _rawPointTraceData = [NSMutableData dataWithLength:(NSUInteger)loaded.scanCount * sizeof(float)];
    _displayPointTraceData = [NSMutableData dataWithLength:(NSUInteger)loaded.scanCount * sizeof(float)];

    _activePhaseIndex = 0U;
    _selectedScanIndex = [self scanIndexNearestActivePhaseToScanIndex:loaded.scanCount / 2U];
    _selectedPointIndex = loaded.pointsPerScan / 2U;
    _backgroundScanIndex = [self scanIndexNearestActivePhaseToScanIndex:0U];
    _backgroundSubtractEnabled = NO;
    _bandpassFilterEnabled = NO;
    _heatmapXManual = NO;
    _heatmapYManual = NO;
    _heatmapColorManual = NO;
    _timeXManual = NO;
    _timeYManual = NO;
    _cvXManual = NO;
    _cvYManual = NO;
    _waveformXManual = NO;
    _waveformYManual = NO;
    _backgroundSubtractSwitch.on = NO;
    _bandpassFilterSwitch.on = NO;
    [self setInputControlsEnabled:YES];

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
    _waveformPlotView.xTickFormat = @"%.2f";
    _waveformPlotView.yTickFormat = @"%.2f";

    [self copyBackgroundScan];
    [self copySelectedScan];
    [self applyDisplayModes];
    [self rebuildHeatmapImage];
    [self refreshHeatmapTicks];
    [self refreshWaveformProgram];
    [self refreshPlotTitles];
    [self refreshSelectionReadout];
    [self requestPointTraceRefresh];

    _fileLabel.stringValue = [self fileSubtitleForLoadedFile:loaded filename:_pendingOpenPath.lastPathComponent];
    _heroStatusLabel.stringValue = ([self activePhasePeriod] > 1U)
        ? [NSString stringWithFormat:@"Layout verified. Showing phase %lu of %lu; crosshairs snap to that FSCV scan family.",
            (unsigned long)_activePhaseIndex + 1UL,
            (unsigned long)[self activePhasePeriod]]
        : @"Layout verified. Grab a crosshair line to move it; sequence time is used for all time axes.";
}

- (BOOL)copyBackgroundScan
{
    if (_loadedFile == nil) {
        return NO;
    }
    _heatmapView.backgroundScanIndex = _backgroundScanIndex;
    return [_loadedFile copyScanAtIndex:(uint32_t)_backgroundScanIndex intoMutableData:_backgroundScanData min:NULL max:NULL];
}

- (NSUInteger)activePhasePeriod
{
    return (_loadedFile == nil) ? 1U : MAX((NSUInteger)_loadedFile.phasePeriod, 1U);
}

- (NSUInteger)scanIndexNearestActivePhaseToScanIndex:(NSUInteger)scanIndex
{
    if (_loadedFile == nil) {
        return 0U;
    }
    return HDCVNearestScanIndexForPhase(
        scanIndex,
        (NSUInteger)_loadedFile.scanCount,
        _activePhaseIndex,
        [self activePhasePeriod]
    );
}

- (NSUInteger)phaseAlignedBackgroundScanIndexForScan:(NSUInteger)scanIndex
{
    return HDCVPhaseAlignedBackgroundIndex(
        _backgroundScanIndex,
        scanIndex,
        (NSUInteger)_loadedFile.scanCount,
        (NSUInteger)_loadedFile.phasePeriod
    );
}

- (BOOL)copyPhaseAlignedBackgroundScanForSelectedScan
{
    if (_loadedFile == nil) {
        return NO;
    }
    NSUInteger alignedIndex = [self phaseAlignedBackgroundScanIndexForScan:_selectedScanIndex];
    return [_loadedFile copyScanAtIndex:(uint32_t)alignedIndex intoMutableData:_selectedPhaseBackgroundScanData min:NULL max:NULL];
}

- (BOOL)copySelectedScan
{
    if (_loadedFile == nil) {
        return NO;
    }
    if (![_loadedFile copyScanAtIndex:(uint32_t)_selectedScanIndex intoMutableData:_selectedRawScanData min:NULL max:NULL]) {
        return NO;
    }
    return [self copyPhaseAlignedBackgroundScanForSelectedScan];
}

- (NSData *)cachedBackgroundScanForIndex:(NSUInteger)scanIndex cache:(NSMutableDictionary<NSNumber *, NSData *> *)cache
{
    NSNumber *key = @(scanIndex);
    NSData *cached = cache[key];
    if (cached != nil) {
        return cached;
    }

    NSMutableData *buffer = [NSMutableData dataWithLength:(NSUInteger)_loadedFile.pointsPerScan * sizeof(float)];
    if (![_loadedFile copyScanAtIndex:(uint32_t)scanIndex intoMutableData:buffer min:NULL max:NULL]) {
        return nil;
    }
    NSData *frozen = [buffer copy];
    cache[key] = frozen;
    return frozen;
}

- (BOOL)copyAverageScanAroundIndex:(NSUInteger)centerScan
                        halfWindow:(NSUInteger)halfWindow
                    intoMutableData:(NSMutableData *)destination
{
    if (_loadedFile == nil) {
        return NO;
    }

    NSUInteger scanCount = _loadedFile.scanCount;
    NSUInteger pointsPerScan = _loadedFile.pointsPerScan;
    NSUInteger period = [self activePhasePeriod];
    NSUInteger center = [self scanIndexNearestActivePhaseToScanIndex:centerScan];
    NSInteger start = (NSInteger)center - ((NSInteger)halfWindow * (NSInteger)period);
    NSInteger end = (NSInteger)center + ((NSInteger)halfWindow * (NSInteger)period);
    NSMutableData *scanData = [NSMutableData dataWithLength:pointsPerScan * sizeof(float)];
    NSMutableData *sumsData = [NSMutableData dataWithLength:pointsPerScan * sizeof(double)];
    double *sums = sumsData.mutableBytes;
    NSUInteger usedCount = 0U;

    destination.length = pointsPerScan * sizeof(float);
    while (start < 0) {
        start += (NSInteger)period;
    }
    while (end >= (NSInteger)scanCount) {
        end -= (NSInteger)period;
    }

    for (NSInteger scanIndex = start; scanIndex <= end; scanIndex += (NSInteger)period) {
        if (scanIndex < 0 || scanIndex >= (NSInteger)scanCount) {
            continue;
        }
        if (![_loadedFile copyScanAtIndex:(uint32_t)scanIndex intoMutableData:scanData min:NULL max:NULL]) {
            return NO;
        }
        const float *scan = scanData.bytes;
        for (NSUInteger pointIndex = 0U; pointIndex < pointsPerScan; ++pointIndex) {
            sums[pointIndex] += (double)scan[pointIndex];
        }
        usedCount += 1U;
    }

    if (usedCount == 0U) {
        return [_loadedFile copyScanAtIndex:(uint32_t)center intoMutableData:destination min:NULL max:NULL];
    }

    float *average = destination.mutableBytes;
    double invCount = 1.0 / (double)usedCount;
    for (NSUInteger pointIndex = 0U; pointIndex < pointsPerScan; ++pointIndex) {
        average[pointIndex] = (float)(sums[pointIndex] * invCount);
    }
    return YES;
}

- (BOOL)copyBandpassFilteredSelectedScanIntoDisplayBuffer
{
    NSUInteger scanCount;
    NSUInteger pointsPerScan;
    NSMutableData *traceData;
    NSMutableData *sourceTraceData;
    float *displayScan;

    if (_loadedFile == nil) {
        return NO;
    }

    scanCount = _loadedFile.scanCount;
    pointsPerScan = _loadedFile.pointsPerScan;
    traceData = [NSMutableData dataWithLength:scanCount * sizeof(float)];
    sourceTraceData = _backgroundSubtractEnabled ? [NSMutableData dataWithLength:scanCount * sizeof(float)] : nil;
    displayScan = _displayScanData.mutableBytes;

    for (NSUInteger pointIndex = 0U; pointIndex < pointsPerScan; ++pointIndex) {
        if (![_loadedFile copyPointTraceAtIndex:(uint32_t)pointIndex intoMutableData:traceData min:NULL max:NULL]) {
            return NO;
        }

        float *trace = traceData.mutableBytes;
        if (_backgroundSubtractEnabled) {
            memcpy(sourceTraceData.mutableBytes, trace, scanCount * sizeof(float));
            HDCVApplyPhaseAlignedBackgroundToTrace(
                sourceTraceData.bytes,
                trace,
                scanCount,
                _backgroundScanIndex,
                (NSUInteger)_loadedFile.phasePeriod
            );
        }

        (void)HDCVApplyButterworthBandpassByPhase(trace, scanCount, [self activePhasePeriod], _loadedFile.cvfHz);
        displayScan[pointIndex] = trace[_selectedScanIndex];
    }

    HDCVRobustRange(_displayScanData.bytes, pointsPerScan, &_displayScanMin, &_displayScanMax);
    return YES;
}

- (BOOL)copyProcessedCVScanIntoDisplayBuffer
{
    if (_loadedFile == nil) {
        return NO;
    }

    NSUInteger scanCount = _loadedFile.scanCount;
    NSUInteger pointsPerScan = _loadedFile.pointsPerScan;
    NSUInteger period = [self activePhasePeriod];
    NSUInteger selectedCenter = HDCVNearestScanIndexForPhase(_selectedScanIndex, scanCount, _activePhaseIndex, period);
    NSUInteger backgroundCenter = HDCVNearestScanIndexForPhase(_backgroundScanIndex, scanCount, _activePhaseIndex, period);
    float *displayCVScan = _displayCVScanData.mutableBytes;

    if (_backgroundSubtractEnabled && selectedCenter == backgroundCenter) {
        memset(displayCVScan, 0, pointsPerScan * sizeof(float));
        _displayCVScanMin = 0.0f;
        _displayCVScanMax = 0.0f;
        return YES;
    }

    if (_bandpassFilterEnabled) {
        NSMutableData *traceData = [NSMutableData dataWithLength:scanCount * sizeof(float)];
        NSMutableData *sourceTraceData = _backgroundSubtractEnabled ? [NSMutableData dataWithLength:scanCount * sizeof(float)] : nil;

        for (NSUInteger pointIndex = 0U; pointIndex < pointsPerScan; ++pointIndex) {
            if (![_loadedFile copyPointTraceAtIndex:(uint32_t)pointIndex intoMutableData:traceData min:NULL max:NULL]) {
                return NO;
            }

            float *trace = traceData.mutableBytes;
            if (_backgroundSubtractEnabled) {
                memcpy(sourceTraceData.mutableBytes, trace, scanCount * sizeof(float));
                HDCVApplyPhaseAlignedBackgroundToTrace(
                    sourceTraceData.bytes,
                    trace,
                    scanCount,
                    _backgroundScanIndex,
                    [self activePhasePeriod]
                );
            }
            (void)HDCVApplyButterworthBandpassByPhase(trace, scanCount, [self activePhasePeriod], _loadedFile.cvfHz);
            displayCVScan[pointIndex] = HDCVAverageTraceInPhaseWindow(
                trace,
                scanCount,
                selectedCenter,
                _activePhaseIndex,
                period,
                HDCVCVSelectedHalfWindow
            );
        }
    } else {
        NSMutableData *selectedAverageData = [NSMutableData dataWithLength:pointsPerScan * sizeof(float)];
        NSMutableData *backgroundAverageData = [NSMutableData dataWithLength:pointsPerScan * sizeof(float)];
        if (![self copyAverageScanAroundIndex:_selectedScanIndex halfWindow:HDCVCVSelectedHalfWindow intoMutableData:selectedAverageData]) {
            return NO;
        }
        const float *selectedAverage = selectedAverageData.bytes;
        const float *backgroundAverage = NULL;
        if (_backgroundSubtractEnabled) {
            if (![self copyAverageScanAroundIndex:backgroundCenter halfWindow:HDCVCVSelectedHalfWindow intoMutableData:backgroundAverageData]) {
                return NO;
            }
            backgroundAverage = backgroundAverageData.bytes;
        }

        for (NSUInteger pointIndex = 0U; pointIndex < pointsPerScan; ++pointIndex) {
            displayCVScan[pointIndex] = selectedAverage[pointIndex] - ((backgroundAverage != NULL) ? backgroundAverage[pointIndex] : 0.0f);
        }
    }

    if (_backgroundSubtractEnabled) {
        HDCVApplyBackgroundSubtractedCVDenoise(displayCVScan, _loadedFile.voltageData.bytes, pointsPerScan);
    }

    HDCVRobustRange(_displayCVScanData.bytes, pointsPerScan, &_displayCVScanMin, &_displayCVScanMax);
    return YES;
}

- (void)applyDisplayModes
{
    if (_loadedFile == nil) {
        return;
    }

    const float *selectedRaw = _selectedRawScanData.bytes;
    const float *selectedPhaseBackground = _selectedPhaseBackgroundScanData.bytes;
    float *displayScan = _displayScanData.mutableBytes;
    NSUInteger pointsPerScan = _loadedFile.pointsPerScan;
    NSUInteger scanCount = _loadedFile.scanCount;

    if (!(_bandpassFilterEnabled && [self copyBandpassFilteredSelectedScanIntoDisplayBuffer])) {
        for (NSUInteger i = 0U; i < pointsPerScan; ++i) {
            displayScan[i] = _backgroundSubtractEnabled ? (selectedRaw[i] - selectedPhaseBackground[i]) : selectedRaw[i];
        }
        HDCVRobustRange(_displayScanData.bytes, pointsPerScan, &_displayScanMin, &_displayScanMax);
    }

    if (![self copyProcessedCVScanIntoDisplayBuffer]) {
        memcpy(_displayCVScanData.mutableBytes, _displayScanData.bytes, pointsPerScan * sizeof(float));
        _displayCVScanMin = _displayScanMin;
        _displayCVScanMax = _displayScanMax;
    }

    if (_rawPointTraceData.length >= scanCount * sizeof(float)) {
        const float *rawTrace = _rawPointTraceData.bytes;
        float *displayTrace = _displayPointTraceData.mutableBytes;
        for (NSUInteger i = 0U; i < scanCount; ++i) {
            NSUInteger alignedIndex = [self phaseAlignedBackgroundScanIndexForScan:i];
            displayTrace[i] = _backgroundSubtractEnabled ? (rawTrace[i] - rawTrace[alignedIndex]) : rawTrace[i];
        }
        if (_bandpassFilterEnabled) {
            (void)HDCVApplyButterworthBandpassByPhase(displayTrace, scanCount, [self activePhasePeriod], _loadedFile.cvfHz);
        }
        HDCVRobustRangeForPhase(_displayPointTraceData.bytes, scanCount, _activePhaseIndex, [self activePhasePeriod], &_displayTraceMin, &_displayTraceMax);
    }

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
        _waveformPlotView.titleText = @"FSCV Waveform";
        _waveformPlotView.subtitleText = @"No file loaded";
        return;
    }

    float selectedVoltage = [_loadedFile voltageAtPoint:_selectedPointIndex];
    double selectedTime = [self selectedScanTime];
    double selectedWaveformTimeMs = [_loadedFile withinScanTimeSecondsAtPoint:_selectedPointIndex] * 1000.0;
    const float *displayScan = _displayScanData.bytes;
    const float *displayCVScan = _displayCVScanData.bytes;
    float selectedCurrent = displayScan[_selectedPointIndex];
    float selectedCVCurrent = displayCVScan[_selectedPointIndex];
    float selectedTimeCurrent = selectedCurrent;
    if (_displayPointTraceData.length >= (NSUInteger)_loadedFile.scanCount * sizeof(float)) {
        const float *displayTrace = _displayPointTraceData.bytes;
        selectedTimeCurrent = displayTrace[_selectedScanIndex];
    }
    NSString *colorSummary = [NSString stringWithFormat:@"[%.3f s ; %.3f V ; %.3f nA]", selectedTime, selectedVoltage, selectedCurrent];
    NSString *timeSummary = [NSString stringWithFormat:@"[%.3f s ; %.3f nA]", selectedTime, selectedTimeCurrent];
    NSString *cvSummary = [NSString stringWithFormat:@"[%.3f V ; %.3f nA]", selectedVoltage, selectedCVCurrent];
    NSString *waveformSummary = [NSString stringWithFormat:@"[%.3f ms ; %.3f V]", selectedWaveformTimeMs, selectedVoltage];
    _heatmapView.titleText = @"Color Plot";
    _heatmapView.subtitleText = colorSummary;

    _timePlotView.titleText = @"I-t Plot";
    _timePlotView.subtitleText = timeSummary;
    _timePlotView.xLabelText = @"Sequence Time (s)";
    _timePlotView.yLabelText = @"Current (nA)";

    _cvPlotView.titleText = @"CV Plot";
    _cvPlotView.subtitleText = cvSummary;
    _cvPlotView.yLabelText = @"Current (nA)";

    _waveformPlotView.titleText = @"FSCV Waveform";
    _waveformPlotView.subtitleText = waveformSummary;
}

- (void)refreshHeatmapTicks
{
    if (_loadedFile == nil) {
        return;
    }

    NSMutableArray<NSString *> *labels = [NSMutableArray array];
    NSMutableArray<NSNumber *> *fractions = [NSMutableArray array];
    NSUInteger tickCount = 5U;
    NSUInteger minScan = _heatmapView.visibleScanMinIndex;
    NSUInteger maxScan = _heatmapView.visibleScanMaxIndex;
    if (maxScan == NSNotFound || maxScan >= _loadedFile.scanCount) {
        maxScan = _loadedFile.scanCount - 1U;
    }
    minScan = MIN(minScan, maxScan);

    for (NSUInteger i = 0U; i < tickCount; ++i) {
        NSUInteger scanIndex = (tickCount == 1U)
            ? minScan
            : minScan + (NSUInteger)llround((double)i * (double)(maxScan - minScan) / (double)(tickCount - 1U));
        double timeValue = [self timeValueForScanIndex:scanIndex];
        [labels addObject:[NSString stringWithFormat:@"%.1f s", timeValue]];
        [fractions addObject:@(maxScan > minScan ? (double)(scanIndex - minScan) / (double)(maxScan - minScan) : 0.0)];
    }

    _heatmapView.xTickLabels = labels;
    _heatmapView.xTickFractions = fractions;
}

- (void)refreshWaveformProgram
{
    if (_waveformProgramView == nil) {
        return;
    }

    if (_loadedFile == nil || _loadedFile.waveformData.length == 0U) {
        _waveformProgramView.rows = @[];
        _waveformProgramView.summaryText = @"No waveform loaded";
    } else {
        NSString *summary = nil;
        NSArray<NSDictionary<NSString *, NSString *> *> *rows = HDCVBuildWaveformProgramRows(
            _loadedFile.waveformData.bytes,
            (NSUInteger)_loadedFile.waveformPointCount,
            _loadedFile.sampleRateHz,
            _loadedFile.waveformFullDurationSeconds * 1000.0,
            &summary
        );
        _waveformProgramView.rows = rows;
        _waveformProgramView.summaryText = (summary != nil) ? summary : @"";
    }

    if (_waveformProgramScrollView != nil) {
        CGFloat width = MAX(_waveformProgramScrollView.contentSize.width, 340.0);
        CGFloat height = MAX(_waveformProgramScrollView.contentSize.height, [_waveformProgramView preferredContentHeight]);
        _waveformProgramView.frame = NSMakeRect(0.0, 0.0, width, height);
    }
}

- (NSImage *)buildHeatmapImage
{
    NSUInteger width = _loadedFile.overviewColumnCount;
    NSUInteger height = _loadedFile.pointsPerScan;
    const float *overview = _loadedFile.overviewData.bytes;
    NSMutableDictionary<NSNumber *, NSData *> *backgroundCache = [NSMutableDictionary dictionary];
    NSMutableData *displayData = [NSMutableData dataWithLength:width * height * sizeof(float)];
    float *displayValues = displayData.mutableBytes;
    NSMutableData *pixelData = [NSMutableData dataWithLength:width * height * 4U];
    unsigned char *pixels = pixelData.mutableBytes;
    float dataMin = 0.0f;
    float dataMax = 0.0f;
    double colorMin;
    double colorMax;

    if (_backgroundSubtractEnabled || [self activePhasePeriod] > 1U) {
        NSMutableData *scanData = [NSMutableData dataWithLength:height * sizeof(float)];
        NSMutableData *sumsData = [NSMutableData dataWithLength:height * sizeof(double)];
        double *sums = sumsData.mutableBytes;
        NSUInteger period = [self activePhasePeriod];

        for (NSUInteger x = 0U; x < width; ++x) {
            NSUInteger startScan = (NSUInteger)(((uint64_t)x * (uint64_t)_loadedFile.scanCount) / (uint64_t)width);
            NSUInteger endScan = (NSUInteger)(((uint64_t)(x + 1U) * (uint64_t)_loadedFile.scanCount) / (uint64_t)width);
            NSUInteger usedScanCount = 0U;
            if (endScan <= startScan) {
                endScan = startScan + 1U;
            }
            endScan = MIN(endScan, (NSUInteger)_loadedFile.scanCount);
            memset(sums, 0, height * sizeof(double));

            for (NSUInteger scanIndex = startScan; scanIndex < endScan; ++scanIndex) {
                if (!HDCVScanIndexMatchesPhase(scanIndex, _activePhaseIndex, period)) {
                    continue;
                }
                if (![_loadedFile copyScanAtIndex:(uint32_t)scanIndex intoMutableData:scanData min:NULL max:NULL]) {
                    continue;
                }

                NSUInteger backgroundIndex = [self phaseAlignedBackgroundScanIndexForScan:scanIndex];
                NSData *backgroundData = _backgroundSubtractEnabled
                    ? [self cachedBackgroundScanForIndex:backgroundIndex cache:backgroundCache]
                    : nil;
                const float *scan = scanData.bytes;
                const float *background = backgroundData.bytes;
                for (NSUInteger pointIndex = 0U; pointIndex < height; ++pointIndex) {
                    float backgroundValue = (_backgroundSubtractEnabled && background != NULL) ? background[pointIndex] : 0.0f;
                    sums[pointIndex] += (double)(scan[pointIndex] - backgroundValue);
                }
                usedScanCount += 1U;
            }

            if (usedScanCount == 0U) {
                NSUInteger midpointScan = startScan + ((endScan - startScan) / 2U);
                NSUInteger scanIndex = [self scanIndexNearestActivePhaseToScanIndex:midpointScan];
                if ([_loadedFile copyScanAtIndex:(uint32_t)scanIndex intoMutableData:scanData min:NULL max:NULL]) {
                    NSUInteger backgroundIndex = [self phaseAlignedBackgroundScanIndexForScan:scanIndex];
                    NSData *backgroundData = _backgroundSubtractEnabled
                        ? [self cachedBackgroundScanForIndex:backgroundIndex cache:backgroundCache]
                        : nil;
                    const float *scan = scanData.bytes;
                    const float *background = backgroundData.bytes;
                    for (NSUInteger pointIndex = 0U; pointIndex < height; ++pointIndex) {
                        float backgroundValue = (_backgroundSubtractEnabled && background != NULL) ? background[pointIndex] : 0.0f;
                        sums[pointIndex] += (double)(scan[pointIndex] - backgroundValue);
                    }
                    usedScanCount = 1U;
                }
            }

            double invCount = 1.0 / (double)MAX((NSUInteger)1U, usedScanCount);
            for (NSUInteger pointIndex = 0U; pointIndex < height; ++pointIndex) {
                displayValues[pointIndex * width + x] = (float)(sums[pointIndex] * invCount);
            }
        }
    } else {
        for (NSUInteger x = 0U; x < width; ++x) {
            for (NSUInteger pointIndex = 0U; pointIndex < height; ++pointIndex) {
                displayValues[pointIndex * width + x] = overview[pointIndex * width + x];
            }
        }
    }

    if (_bandpassFilterEnabled) {
        double duration = MAX([self timeValueForScanIndex:_loadedFile.scanCount - 1U] - [self timeValueForScanIndex:0U], 1.0e-9);
        double overviewSampleRate = (double)width / duration;
        for (NSUInteger pointIndex = 0U; pointIndex < height; ++pointIndex) {
            (void)HDCVApplyButterworthBandpass(displayValues + (pointIndex * width), width, overviewSampleRate);
        }
    }

    if (!HDCVFiniteRange(displayValues, width * height, &dataMin, &dataMax)) {
        dataMin = -1.0f;
        dataMax = 1.0f;
    }
    colorMin = _heatmapColorManual ? _heatmapColorMinManual : (double)dataMin;
    colorMax = _heatmapColorManual ? _heatmapColorMaxManual : (double)dataMax;
    HDCVNormalizeDivergingColorLimits(&colorMin, &colorMax);

    for (NSUInteger pointIndex = 0U; pointIndex < height; ++pointIndex) {
        NSUInteger y = height - 1U - pointIndex;
        for (NSUInteger x = 0U; x < width; ++x) {
            float value = displayValues[pointIndex * width + x];
            float normalized = HDCVNormalizeCurrentForColor(value, colorMin, colorMax);
            NSUInteger offset = (y * width + x) * 4U;
            float r;
            float g;
            float b;

            HDCVHeatmapRGBForNormalized(normalized, &r, &g, &b);

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
    _heatmapView.colorScaleMinNA = colorMin;
    _heatmapView.colorScaleMaxNA = colorMax;
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
    return [_loadedFile sequenceTimeSecondsAtScan:scanIndex];
}

- (double)selectedScanTime
{
    return [self timeValueForScanIndex:_selectedScanIndex];
}

- (NSString *)fileSubtitleForLoadedFile:(HDCVLoadedFile *)loaded filename:(NSString *)filename
{
    double sampleRate = loaded.sampleRateHz;
    NSString *sampleRateText;
    double totalDuration = (double)loaded.scanCount * loaded.scanIntervalSeconds;

    if (sampleRate >= 1000.0) {
        sampleRateText = [NSString stringWithFormat:@"%.1f kHz", sampleRate / 1000.0];
    } else {
        sampleRateText = [NSString stringWithFormat:@"%.1f Hz", sampleRate];
    }
    return [NSString stringWithFormat:@"%@  |  %@  |  %.1f s", filename, sampleRateText, totalDuration];
}

- (void)refreshControlFields
{
    if (_loadedFile == nil) {
        for (NSTextField *field in @[
            _heatmapScanField, _heatmapPointField, _heatmapBackgroundField,
            _timeScanField, _timeBackgroundField, _cvPointField
        ]) {
            field.stringValue = @"";
        }
        return;
    }

    NSString *scanText = [NSString stringWithFormat:@"%.3f", [self timeValueForScanIndex:_selectedScanIndex]];
    NSString *pointText = [NSString stringWithFormat:@"%.3f", [_loadedFile voltageAtPoint:_selectedPointIndex]];
    NSString *backgroundText = [NSString stringWithFormat:@"%.3f", [self timeValueForScanIndex:_backgroundScanIndex]];

    _heatmapScanField.stringValue = scanText;
    _timeScanField.stringValue = scanText;
    _heatmapPointField.stringValue = pointText;
    _cvPointField.stringValue = pointText;
    _heatmapBackgroundField.stringValue = backgroundText;
    _timeBackgroundField.stringValue = backgroundText;
}

- (void)refreshPlots
{
    if (_loadedFile == nil) {
        return;
    }

    _heatmapView.selectedScanIndex = _selectedScanIndex;
    _heatmapView.selectedPointIndex = _selectedPointIndex;
    _heatmapView.backgroundScanIndex = _backgroundScanIndex;
    _heatmapView.visibleScanMinIndex = _heatmapXManual
        ? (NSUInteger)llround(MAX(0.0, MIN((double)(_loadedFile.scanCount - 1U), _heatmapXMinManual)))
        : 0U;
    _heatmapView.visibleScanMaxIndex = _heatmapXManual
        ? (NSUInteger)llround(MAX(0.0, MIN((double)(_loadedFile.scanCount - 1U), _heatmapXMaxManual)))
        : _loadedFile.scanCount - 1U;
    if (_heatmapView.visibleScanMaxIndex <= _heatmapView.visibleScanMinIndex && _heatmapView.visibleScanMinIndex < _loadedFile.scanCount - 1U) {
        _heatmapView.visibleScanMaxIndex = _heatmapView.visibleScanMinIndex + 1U;
    }
    _heatmapView.visiblePointMinIndex = _heatmapYManual
        ? (NSUInteger)llround(MAX(0.0, MIN((double)(_loadedFile.pointsPerScan - 1U), _heatmapYMinManual)))
        : 0U;
    _heatmapView.visiblePointMaxIndex = _heatmapYManual
        ? (NSUInteger)llround(MAX(0.0, MIN((double)(_loadedFile.pointsPerScan - 1U), _heatmapYMaxManual)))
        : _loadedFile.pointsPerScan - 1U;
    if (_heatmapView.visiblePointMaxIndex <= _heatmapView.visiblePointMinIndex && _heatmapView.visiblePointMinIndex < _loadedFile.pointsPerScan - 1U) {
        _heatmapView.visiblePointMaxIndex = _heatmapView.visiblePointMinIndex + 1U;
    }
    [self refreshHeatmapTicks];

    double yMin = (double)_displayCVScanMin;
    double yMax = (double)_displayCVScanMax;
    const float *voltage = _loadedFile.voltageData.bytes;
    double voltageMin = (double)voltage[0];
    double voltageMax = (double)voltage[0];
    for (NSUInteger i = 1U; i < _loadedFile.pointsPerScan; ++i) {
        voltageMin = MIN(voltageMin, (double)voltage[i]);
        voltageMax = MAX(voltageMax, (double)voltage[i]);
    }
    HDCVExpandRange(&yMin, &yMax);
    HDCVExpandRange(&voltageMin, &voltageMax);
    HDCVExpandRangeToIncludeZero(&yMin, &yMax);
    HDCVExpandRangeToIncludeZero(&voltageMin, &voltageMax);
    _cvPlotView.xMin = _cvXManual ? _cvXMinManual : voltageMin;
    _cvPlotView.xMax = _cvXManual ? _cvXMaxManual : voltageMax;
    _cvPlotView.yMin = _cvYManual ? _cvYMinManual : yMin;
    _cvPlotView.yMax = _cvYManual ? _cvYMaxManual : yMax;
    _cvPlotView.selectedXValue = [_loadedFile voltageAtPoint:_selectedPointIndex];
    _cvPlotView.selectedYValue = ((const float *)_displayCVScanData.bytes)[_selectedPointIndex];
    _cvPlotView.showsSelection = YES;
    _cvPlotView.showsBaseline = _backgroundSubtractEnabled;
    _cvPlotView.showsBackgroundX = NO;
    _cvPlotView.baselineYValue = 0.0;
    [_cvPlotView setNeedsDisplay:YES];

    if (_displayPointTraceData.length >= _loadedFile.scanCount * sizeof(float)) {
        double traceMin = (double)_displayTraceMin;
        double traceMax = (double)_displayTraceMax;
        NSUInteger phaseSampleCount = HDCVPhaseSampleCount((NSUInteger)_loadedFile.scanCount, _activePhaseIndex, [self activePhasePeriod]);
        NSUInteger firstPhaseScan = HDCVScanIndexForPhaseSample(0U, (NSUInteger)_loadedFile.scanCount, _activePhaseIndex, [self activePhasePeriod]);
        NSUInteger lastPhaseScan = HDCVScanIndexForPhaseSample(phaseSampleCount > 0U ? phaseSampleCount - 1U : 0U, (NSUInteger)_loadedFile.scanCount, _activePhaseIndex, [self activePhasePeriod]);
        double traceXMin = [self timeValueForScanIndex:firstPhaseScan];
        double traceXMax = [self timeValueForScanIndex:lastPhaseScan];
        HDCVExpandRange(&traceMin, &traceMax);
        HDCVExpandRangeToIncludeZero(&traceXMin, &traceXMax);
        if (_backgroundSubtractEnabled) {
            HDCVExpandRangeToIncludeZero(&traceMin, &traceMax);
        }
        _timePlotView.xMin = _timeXManual ? _timeXMinManual : traceXMin;
        _timePlotView.xMax = _timeXManual ? _timeXMaxManual : traceXMax;
        _timePlotView.yMin = _timeYManual ? _timeYMinManual : traceMin;
        _timePlotView.yMax = _timeYManual ? _timeYMaxManual : traceMax;
        _timePlotView.selectedXValue = [self selectedScanTime];
        _timePlotView.selectedYValue = ((const float *)_displayPointTraceData.bytes)[_selectedScanIndex];
        _timePlotView.showsSelection = YES;
        _timePlotView.showsBaseline = _backgroundSubtractEnabled;
        _timePlotView.showsBackgroundX = YES;
        _timePlotView.backgroundXValue = [self timeValueForScanIndex:_backgroundScanIndex];
        _timePlotView.baselineYValue = 0.0;
        [_timePlotView setNeedsDisplay:YES];
    }

    {
        double waveformXMin = 0.0;
        double waveformXMax = HDCVWaveformFullDisplayDurationMs(
            (NSUInteger)_loadedFile.waveformPointCount,
            (NSUInteger)_loadedFile.waveformFullPointCount,
            _loadedFile.sampleRateHz);
        const float *waveform = _loadedFile.waveformData.bytes;
        double waveformYMin = (double)waveform[0];
        double waveformYMax = (double)waveform[0];
        for (NSUInteger i = 1U; i < _loadedFile.waveformPointCount; ++i) {
            waveformYMin = MIN(waveformYMin, (double)waveform[i]);
            waveformYMax = MAX(waveformYMax, (double)waveform[i]);
        }
        HDCVExpandRange(&waveformYMin, &waveformYMax);
        HDCVExpandRangeToIncludeZero(&waveformXMin, &waveformXMax);
        HDCVExpandRangeToIncludeZero(&waveformYMin, &waveformYMax);
        _waveformPlotView.xMin = _waveformXManual ? _waveformXMinManual : waveformXMin;
        _waveformPlotView.xMax = _waveformXManual ? _waveformXMaxManual : waveformXMax;
        _waveformPlotView.yMin = _waveformYManual ? _waveformYMinManual : waveformYMin;
        _waveformPlotView.yMax = _waveformYManual ? _waveformYMaxManual : waveformYMax;
        _waveformPlotView.selectedXValue = [_loadedFile withinScanTimeSecondsAtPoint:_selectedPointIndex] * 1000.0;
        _waveformPlotView.selectedYValue = [_loadedFile voltageAtPoint:_selectedPointIndex];
        _waveformPlotView.showsSelection = YES;
        _waveformPlotView.showsBaseline = NO;
        _waveformPlotView.showsBackgroundX = NO;
        [_waveformPlotView setNeedsDisplay:YES];
    }

    [self refreshControlFields];
}

- (void)refreshSelectionReadout
{
    if (_loadedFile == nil) {
        [self refreshControlFields];
        return;
    }
    [self refreshControlFields];
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
            self->_heroStatusLabel.stringValue = @"Interactive FSCV plots are live. Grab crosshair lines to move scan, point, or background positions.";
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

- (BOOL)parseUnsignedIntegerFromField:(NSTextField *)field maxValue:(NSUInteger)maxValue outValue:(NSUInteger *)outValue
{
    const char *text = field.stringValue.UTF8String;
    char *endptr = NULL;
    unsigned long long parsed = strtoull(text, &endptr, 10);
    if (endptr == text) {
        return NO;
    }
    while (*endptr != '\0') {
        if (!isspace((unsigned char)*endptr)) {
            return NO;
        }
        endptr += 1;
    }
    *outValue = (NSUInteger)MIN(parsed, (unsigned long long)maxValue);
    return YES;
}

- (void)controlTextDidEndEditing:(NSNotification *)notification
{
    NSTextField *field = notification.object;
    if (![field isKindOfClass:NSTextField.class]) {
        return;
    }
    if (field == _heatmapScanField || field == _timeScanField ||
        field == _heatmapPointField || field == _cvPointField ||
        field == _heatmapBackgroundField || field == _timeBackgroundField) {
        [self selectionFieldChanged:field];
    }
}

- (void)selectionFieldChanged:(id)sender
{
    if (_loadedFile == nil || ![sender isKindOfClass:NSTextField.class]) {
        return;
    }

    NSTextField *field = sender;
    double value = 0.0;

    if (field == _heatmapScanField || field == _timeScanField) {
        if (!HDCVParseLeadingDouble(field.stringValue, &value)) {
            [self refreshControlFields];
            return;
        }
        _selectedScanIndex = [self scanIndexNearestTimeValue:value];
        [self openOrRefreshAfterSelectionChangeNeedsTrace:NO];
    } else if (field == _heatmapPointField || field == _cvPointField) {
        if (!HDCVParseLeadingDouble(field.stringValue, &value)) {
            [self refreshControlFields];
            return;
        }
        _selectedPointIndex = [self pointIndexNearestVoltageValue:value];
        [self openOrRefreshAfterSelectionChangeNeedsTrace:YES];
    } else if (field == _heatmapBackgroundField || field == _timeBackgroundField) {
        if (!HDCVParseLeadingDouble(field.stringValue, &value)) {
            [self refreshControlFields];
            return;
        }
        _backgroundScanIndex = [self scanIndexNearestTimeValue:value];
        [self copyBackgroundScan];
        [self copyPhaseAlignedBackgroundScanForSelectedScan];
        [self applyDisplayModes];
        [self rebuildHeatmapImage];
        [self refreshSelectionReadout];
        _heroStatusLabel.stringValue = [NSString stringWithFormat:@"Background time set to %.3f s.", [self timeValueForScanIndex:_backgroundScanIndex]];
    }
}

- (NSUInteger)scanIndexNearestTimeValue:(double)xValue
{
    if (_loadedFile == nil || _loadedFile.scanCount == 0U) {
        return 0U;
    }
    double interval = MAX(_loadedFile.scanIntervalSeconds, 1.0e-12);
    double scanValue = xValue / interval;
    NSUInteger rawNearest = (NSUInteger)llround(MAX(0.0, MIN((double)(_loadedFile.scanCount - 1U), scanValue)));
    return [self scanIndexNearestActivePhaseToScanIndex:rawNearest];
}

- (NSUInteger)pointIndexForHeatmapAxisValue:(double)value
{
    if (_loadedFile == nil || _loadedFile.pointsPerScan == 0U) {
        return 0U;
    }

    if (fabs(value) > 5.0) {
        return (NSUInteger)llround(MAX(0.0, MIN((double)(_loadedFile.pointsPerScan - 1U), value)));
    }

    const float *voltage = _loadedFile.voltageData.bytes;
    NSUInteger bestIndex = 0U;
    double bestDistance = DBL_MAX;
    NSUInteger referencePoint = MIN(_selectedPointIndex, (NSUInteger)_loadedFile.pointsPerScan - 1U);
    for (NSUInteger pointIndex = 0U; pointIndex < _loadedFile.pointsPerScan; ++pointIndex) {
        double distance = fabs((double)voltage[pointIndex] - value);
        if (distance < bestDistance ||
            (fabs(distance - bestDistance) <= 1.0e-9 &&
             llabs((long long)pointIndex - (long long)referencePoint) < llabs((long long)bestIndex - (long long)referencePoint))) {
            bestDistance = distance;
            bestIndex = pointIndex;
        }
    }
    return bestIndex;
}

- (NSUInteger)pointIndexNearestVoltageValue:(double)value
{
    if (_loadedFile == nil || _loadedFile.pointsPerScan == 0U) {
        return 0U;
    }

    const float *voltage = _loadedFile.voltageData.bytes;
    NSUInteger bestIndex = 0U;
    double bestDistance = DBL_MAX;
    for (NSUInteger pointIndex = 0U; pointIndex < _loadedFile.pointsPerScan; ++pointIndex) {
        double distance = fabs((double)voltage[pointIndex] - value);
        if (distance < bestDistance) {
            bestDistance = distance;
            bestIndex = pointIndex;
        }
    }
    return bestIndex;
}

- (BOOL)applyRangeEditTarget:(HDCVAxisEditTarget)target
                       value:(double)value
                     minSlot:(double *)minSlot
                     maxSlot:(double *)maxSlot
                  manualFlag:(BOOL *)manualFlag
                  currentMin:(double)currentMin
                  currentMax:(double)currentMax
{
    double newMin = currentMin;
    double newMax = currentMax;

    if (target == HDCVAxisEditTargetXMin || target == HDCVAxisEditTargetYMin) {
        newMin = value;
    } else if (target == HDCVAxisEditTargetXMax || target == HDCVAxisEditTargetYMax) {
        newMax = value;
    }

    if (!isfinite(newMin) || !isfinite(newMax) || newMax <= newMin) {
        _heroStatusLabel.stringValue = @"Axis range needs a numeric min smaller than max.";
        return NO;
    }

    *manualFlag = YES;
    *minSlot = newMin;
    *maxSlot = newMax;
    return YES;
}

- (void)syncTimeRangeToHeatmap
{
    if (_loadedFile == nil || !_timeXManual) {
        return;
    }
    NSUInteger minScan = [self scanIndexNearestTimeValue:_timeXMinManual];
    NSUInteger maxScan = [self scanIndexNearestTimeValue:_timeXMaxManual];
    if (maxScan <= minScan && minScan < _loadedFile.scanCount - 1U) {
        maxScan = minScan + 1U;
    }
    _heatmapXManual = YES;
    _heatmapXMinManual = (double)minScan;
    _heatmapXMaxManual = (double)maxScan;
}

- (void)syncHeatmapRangeToTime
{
    if (_loadedFile == nil || !_heatmapXManual) {
        return;
    }
    NSUInteger minScan = (NSUInteger)llround(MAX(0.0, MIN((double)(_loadedFile.scanCount - 1U), _heatmapXMinManual)));
    NSUInteger maxScan = (NSUInteger)llround(MAX(0.0, MIN((double)(_loadedFile.scanCount - 1U), _heatmapXMaxManual)));
    if (maxScan <= minScan && minScan < _loadedFile.scanCount - 1U) {
        maxScan = minScan + 1U;
    }
    _timeXManual = YES;
    _timeXMinManual = [self timeValueForScanIndex:minScan];
    _timeXMaxManual = [self timeValueForScanIndex:maxScan];
}

- (void)heatmapView:(HDCVHeatmapView *)view didEditAxisTarget:(HDCVAxisEditTarget)target value:(double)value
{
    (void)view;
    if (_loadedFile == nil) {
        return;
    }

    if (target == HDCVAxisEditTargetXMin || target == HDCVAxisEditTargetXMax) {
        double minScan = _heatmapXManual ? _heatmapXMinManual : 0.0;
        double maxScan = _heatmapXManual ? _heatmapXMaxManual : (double)(_loadedFile.scanCount - 1U);
        double editedScan = (double)[self scanIndexNearestTimeValue:value];
        if (![self applyRangeEditTarget:target value:editedScan minSlot:&_heatmapXMinManual maxSlot:&_heatmapXMaxManual manualFlag:&_heatmapXManual currentMin:minScan currentMax:maxScan]) {
            return;
        }
        [self syncHeatmapRangeToTime];
    } else if (target == HDCVAxisEditTargetYMin || target == HDCVAxisEditTargetYMax) {
        double minPoint = _heatmapYManual ? _heatmapYMinManual : 0.0;
        double maxPoint = _heatmapYManual ? _heatmapYMaxManual : (double)(_loadedFile.pointsPerScan - 1U);
        double editedPoint = (double)[self pointIndexForHeatmapAxisValue:value];
        if (![self applyRangeEditTarget:target value:editedPoint minSlot:&_heatmapYMinManual maxSlot:&_heatmapYMaxManual manualFlag:&_heatmapYManual currentMin:minPoint currentMax:maxPoint]) {
            return;
        }
    } else if (target == HDCVAxisEditTargetColorMin || target == HDCVAxisEditTargetColorMax) {
        double colorMin = _heatmapColorManual ? _heatmapColorMinManual : _heatmapView.colorScaleMinNA;
        double colorMax = _heatmapColorManual ? _heatmapColorMaxManual : _heatmapView.colorScaleMaxNA;
        if (target == HDCVAxisEditTargetColorMin) {
            colorMin = (value > 0.0) ? -value : value;
        } else {
            colorMax = fabs(value);
        }
        HDCVNormalizeDivergingColorLimits(&colorMin, &colorMax);
        _heatmapColorMinManual = colorMin;
        _heatmapColorMaxManual = colorMax;
        _heatmapColorManual = YES;
        [self rebuildHeatmapImage];
        _heroStatusLabel.stringValue = @"Color scale updated from the legend.";
        return;
    }

    [self refreshPlots];
    _heroStatusLabel.stringValue = @"Axis range updated from the plot.";
}

- (void)linePlotView:(HDCVLinePlotView *)view didEditAxisTarget:(HDCVAxisEditTarget)target value:(double)value
{
    if (_loadedFile == nil) {
        return;
    }

    if (view == _timePlotView) {
        if (target == HDCVAxisEditTargetXMin || target == HDCVAxisEditTargetXMax) {
            if (![self applyRangeEditTarget:target value:value minSlot:&_timeXMinManual maxSlot:&_timeXMaxManual manualFlag:&_timeXManual currentMin:_timePlotView.xMin currentMax:_timePlotView.xMax]) {
                return;
            }
            [self syncTimeRangeToHeatmap];
        } else {
            if (![self applyRangeEditTarget:target value:value minSlot:&_timeYMinManual maxSlot:&_timeYMaxManual manualFlag:&_timeYManual currentMin:_timePlotView.yMin currentMax:_timePlotView.yMax]) {
                return;
            }
        }
    } else if (view == _cvPlotView) {
        if (target == HDCVAxisEditTargetXMin || target == HDCVAxisEditTargetXMax) {
            if (![self applyRangeEditTarget:target value:value minSlot:&_cvXMinManual maxSlot:&_cvXMaxManual manualFlag:&_cvXManual currentMin:_cvPlotView.xMin currentMax:_cvPlotView.xMax]) {
                return;
            }
        } else {
            if (![self applyRangeEditTarget:target value:value minSlot:&_cvYMinManual maxSlot:&_cvYMaxManual manualFlag:&_cvYManual currentMin:_cvPlotView.yMin currentMax:_cvPlotView.yMax]) {
                return;
            }
        }
    } else if (view == _waveformPlotView) {
        if (target == HDCVAxisEditTargetXMin || target == HDCVAxisEditTargetXMax) {
            if (![self applyRangeEditTarget:target value:value minSlot:&_waveformXMinManual maxSlot:&_waveformXMaxManual manualFlag:&_waveformXManual currentMin:_waveformPlotView.xMin currentMax:_waveformPlotView.xMax]) {
                return;
            }
        } else {
            if (![self applyRangeEditTarget:target value:value minSlot:&_waveformYMinManual maxSlot:&_waveformYMaxManual manualFlag:&_waveformYManual currentMin:_waveformPlotView.yMin currentMax:_waveformPlotView.yMax]) {
                return;
            }
        }
    }

    [self refreshPlots];
    _heroStatusLabel.stringValue = @"Axis range updated from the plot.";
}

- (void)linePlotView:(HDCVLinePlotView *)view didNavigateToXMin:(double)xMin xMax:(double)xMax yMin:(double)yMin yMax:(double)yMax
{
    if (_loadedFile == nil) {
        return;
    }

    if (view == _timePlotView) {
        _timeXManual = YES;
        _timeYManual = YES;
        _timeXMinManual = xMin;
        _timeXMaxManual = xMax;
        _timeYMinManual = yMin;
        _timeYMaxManual = yMax;
        [self syncTimeRangeToHeatmap];
        _heroStatusLabel.stringValue = @"I-t view adjusted. Use Reset View to return to automatic scaling.";
    } else if (view == _cvPlotView) {
        _cvXManual = YES;
        _cvYManual = YES;
        _cvXMinManual = xMin;
        _cvXMaxManual = xMax;
        _cvYMinManual = yMin;
        _cvYMaxManual = yMax;
        _heroStatusLabel.stringValue = @"CV view adjusted. Use Reset View to return to automatic scaling.";
    } else {
        return;
    }

    [self refreshPlots];
}

- (void)linePlotViewDidRequestResetView:(HDCVLinePlotView *)view
{
    if (view == _timePlotView) {
        [self resetTimePlotView:nil];
    } else if (view == _cvPlotView) {
        [self resetCVPlotView:nil];
    }
}

- (void)resetTimePlotView:(id)sender
{
    (void)sender;
    if (_loadedFile == nil) {
        return;
    }
    _timeXManual = NO;
    _timeYManual = NO;
    _heatmapXManual = NO;
    [self refreshPlots];
    _heroStatusLabel.stringValue = @"I-t view reset to automatic scaling.";
}

- (void)resetCVPlotView:(id)sender
{
    (void)sender;
    if (_loadedFile == nil) {
        return;
    }
    _cvXManual = NO;
    _cvYManual = NO;
    [self refreshPlots];
    _heroStatusLabel.stringValue = @"CV view reset to automatic scaling.";
}

- (void)backgroundSubtractToggled:(id)sender
{
    (void)sender;
    if (_loadedFile == nil) {
        return;
    }
    _backgroundSubtractEnabled = _backgroundSubtractSwitch.on;
    [self applyDisplayModes];
    [self rebuildHeatmapImage];
    [self refreshSelectionReadout];
    _heroStatusLabel.stringValue = _backgroundSubtractEnabled
        ? @"Background subtraction is enabled across the color plot, I-t plot, and CV plot."
        : @"Background subtraction is disabled. The plots are showing raw current.";
}

- (void)bandpassFilterToggled:(id)sender
{
    (void)sender;
    if (_loadedFile == nil) {
        return;
    }
    _bandpassFilterEnabled = _bandpassFilterSwitch.on;
    [self applyDisplayModes];
    [self rebuildHeatmapImage];
    [self refreshSelectionReadout];
    _heroStatusLabel.stringValue = _bandpassFilterEnabled
        ? @"Butterworth bandpass is enabled across the color plot, I-t plot, and CV plot."
        : @"Butterworth bandpass is disabled.";
}

- (void)useSelectedScanAsBackground:(id)sender
{
    (void)sender;
    if (_loadedFile == nil) {
        return;
    }
    _backgroundScanIndex = _selectedScanIndex;
    [self copyBackgroundScan];
    [self copyPhaseAlignedBackgroundScanForSelectedScan];
    [self applyDisplayModes];
    [self rebuildHeatmapImage];
    [self refreshSelectionReadout];
    _heroStatusLabel.stringValue = [NSString stringWithFormat:@"Background scan updated to the selected scan %lu.", (unsigned long)_backgroundScanIndex];
}

- (void)heatmapView:(HDCVHeatmapView *)view didDragSelectionScanIndex:(NSUInteger)scanIndex pointIndex:(NSUInteger)pointIndex updateScan:(BOOL)updateScan updatePoint:(BOOL)updatePoint
{
    (void)view;
    if (_loadedFile == nil) {
        return;
    }
    if (updateScan) {
        _selectedScanIndex = [self scanIndexNearestActivePhaseToScanIndex:MIN(scanIndex, _loadedFile.scanCount - 1U)];
    }
    if (updatePoint) {
        _selectedPointIndex = MIN(pointIndex, _loadedFile.pointsPerScan - 1U);
    }
    [self openOrRefreshAfterSelectionChangeNeedsTrace:updatePoint];
}

- (void)heatmapView:(HDCVHeatmapView *)view didDragBackgroundScanIndex:(NSUInteger)scanIndex
{
    (void)view;
    if (_loadedFile == nil) {
        return;
    }
    _backgroundScanIndex = [self scanIndexNearestActivePhaseToScanIndex:MIN(scanIndex, _loadedFile.scanCount - 1U)];
    [self copyBackgroundScan];
    [self copyPhaseAlignedBackgroundScanForSelectedScan];
    [self applyDisplayModes];
    [self rebuildHeatmapImage];
    [self refreshSelectionReadout];
}

- (void)linePlotView:(HDCVLinePlotView *)view didDragXValue:(double)xValue yValue:(double)yValue target:(HDCVLinePlotDragTarget)target
{
    if (_loadedFile == nil) {
        return;
    }

    if (view == _timePlotView) {
        NSUInteger bestScanIndex = [self scanIndexNearestTimeValue:xValue];
        if (target == HDCVLinePlotDragTargetBackgroundX) {
            _backgroundScanIndex = bestScanIndex;
            [self copyBackgroundScan];
            [self copyPhaseAlignedBackgroundScanForSelectedScan];
            [self applyDisplayModes];
            [self rebuildHeatmapImage];
            [self refreshSelectionReadout];
        } else {
            _selectedScanIndex = bestScanIndex;
            [self openOrRefreshAfterSelectionChangeNeedsTrace:NO];
        }
    } else if (view == _cvPlotView) {
        NSUInteger bestPointIndex = 0U;
        double bestDistance = DBL_MAX;
        double xRange = MAX(_cvPlotView.xMax - _cvPlotView.xMin, 1.0e-9);
        double yRange = MAX(_cvPlotView.yMax - _cvPlotView.yMin, 1.0e-9);
        const float *displayCVScan = _displayCVScanData.bytes;
        for (NSUInteger pointIndex = 0U; pointIndex < _loadedFile.pointsPerScan; ++pointIndex) {
            double dx = ((double)[_loadedFile voltageAtPoint:pointIndex] - xValue) / xRange;
            double dy = ((double)displayCVScan[pointIndex] - yValue) / yRange;
            double distance = (dx * dx) + (dy * dy);
            if (distance < bestDistance) {
                bestDistance = distance;
                bestPointIndex = pointIndex;
            }
        }
        _selectedPointIndex = bestPointIndex;
        [self openOrRefreshAfterSelectionChangeNeedsTrace:YES];
    } else if (view == _waveformPlotView) {
        double pointValue = (xValue / 1000.0) * _loadedFile.sampleRateHz;
        NSUInteger pointIndex = (NSUInteger)llround(MAX(0.0, MIN((double)(_loadedFile.pointsPerScan - 1U), pointValue)));
        _selectedPointIndex = pointIndex;
        [self openOrRefreshAfterSelectionChangeNeedsTrace:YES];
    }
}

- (NSUInteger)sampleCountForLinePlotView:(HDCVLinePlotView *)view
{
    if (_loadedFile == nil) {
        return 0U;
    }
    if (view == _timePlotView) {
        return HDCVPhaseSampleCount((NSUInteger)_loadedFile.scanCount, _activePhaseIndex, [self activePhasePeriod]);
    }
    if (view == _cvPlotView) {
        return _loadedFile.pointsPerScan;
    }
    if (view == _waveformPlotView) {
        return HDCVWaveformDisplayPointCount(
            (NSUInteger)_loadedFile.waveformPointCount,
            (NSUInteger)_loadedFile.waveformFullPointCount,
            _loadedFile.sampleRateHz);
    }
    return 0U;
}

- (double)linePlotView:(HDCVLinePlotView *)view xValueAtIndex:(NSUInteger)index
{
    if (view == _timePlotView) {
        NSUInteger scanIndex = HDCVScanIndexForPhaseSample(index, (NSUInteger)_loadedFile.scanCount, _activePhaseIndex, [self activePhasePeriod]);
        return [self timeValueForScanIndex:scanIndex];
    }
    if (view == _cvPlotView) {
        return [_loadedFile voltageAtPoint:index];
    }
    if (view == _waveformPlotView) {
        return ((double)index / _loadedFile.sampleRateHz) * 1000.0;
    }
    return 0.0;
}

- (double)linePlotView:(HDCVLinePlotView *)view yValueAtIndex:(NSUInteger)index
{
    if (view == _timePlotView) {
        const float *trace = _displayPointTraceData.bytes;
        NSUInteger scanIndex = HDCVScanIndexForPhaseSample(index, (NSUInteger)_loadedFile.scanCount, _activePhaseIndex, [self activePhasePeriod]);
        return trace[scanIndex];
    }
    if (view == _cvPlotView) {
        const float *scan = _displayCVScanData.bytes;
        return scan[index];
    }
    if (view == _waveformPlotView) {
        const float *waveform = _loadedFile.waveformData.bytes;
        if (index < _loadedFile.waveformPointCount) {
            return waveform[index];
        }
        return waveform[0];
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
