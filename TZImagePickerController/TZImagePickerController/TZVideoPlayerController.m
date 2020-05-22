//
//  TZVideoPlayerController.m
//  TZImagePickerController
//
//  Created by 谭真 on 16/1/5.
//  Copyright © 2016年 谭真. All rights reserved.
//

#import "TZVideoPlayerController.h"
#import <MediaPlayer/MediaPlayer.h>
#import "UIView+Layout.h"
#import "TZImageManager.h"
#import "TZAssetModel.h"
#import "TZImagePickerController.h"
#import "TZPhotoPreviewController.h"

typedef enum : NSUInteger {
    PlayerStatus_None,
    PlayerStatus_Play,
    PlayerStatus_Pause,
    PlayerStatus_End,
} PlayerStatus;

@interface TZVideoPlayerController () {
    AVPlayer *_player;
    AVPlayerLayer *_playerLayer;
    UIButton *_playButton;
    UIImage *_cover;
    
    UIView *_toolBar;
    UIButton *_doneButton;
    
    UIStatusBarStyle _originStatusBarStyle;
    
    BOOL _showSlider;
    UISlider *_slider;
    
    float _fps;
    float _playerDuration;
    PlayerStatus _playerStatus;
    UIView *_sliderToolBar;
    UIButton *_sliderPlayButton;
}
@property (assign, nonatomic) BOOL needShowStatusBar;

@property (nonatomic, assign) BOOL isSliding;
@property (nonatomic, strong) UILabel *sliderCurrentTimeLabel;
@property (nonatomic, strong) UILabel *sliderTotalTimeLabel;

// touch screen controll hide & show when _showSlider
@property (nonatomic, strong) UIControl *touchScreen;

// player current value
@property (nonatomic, assign) float playerCurrent;
@end

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

@implementation TZVideoPlayerController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.needShowStatusBar = ![UIApplication sharedApplication].statusBarHidden;
    self.view.backgroundColor = [UIColor blackColor];
    TZImagePickerController *tzImagePickerVc = (TZImagePickerController *)self.navigationController;
    if (tzImagePickerVc) {
        self.navigationItem.title = tzImagePickerVc.previewBtnTitleStr;
    }
    
    _isSliding = NO;
    _playerStatus = PlayerStatus_None;
    [self configMoviePlayer];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(pausePlayerAndShowNaviBar) name:UIApplicationWillResignActiveNotification object:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    _originStatusBarStyle = [UIApplication sharedApplication].statusBarStyle;
    [UIApplication sharedApplication].statusBarStyle = UIStatusBarStyleLightContent;
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if (self.needShowStatusBar) {
        [UIApplication sharedApplication].statusBarHidden = NO;
    }
    [UIApplication sharedApplication].statusBarStyle = _originStatusBarStyle;
}

- (void)configMoviePlayer {
    [[TZImageManager manager] getPhotoWithAsset:_model.asset completion:^(UIImage *photo, NSDictionary *info, BOOL isDegraded) {
        if (!isDegraded && photo) {
            self->_cover = photo;
            self->_doneButton.enabled = YES;
        }
    }];
    [[TZImageManager manager] getVideoWithAsset:_model.asset completion:^(AVPlayerItem *playerItem, NSDictionary *info) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_player = [AVPlayer playerWithPlayerItem:playerItem];
            self->_playerLayer = [AVPlayerLayer playerLayerWithPlayer:self->_player];
            self->_playerLayer.frame = self.view.bounds;
            [self.view.layer addSublayer:self->_playerLayer];
            [self configPlayButton];
            [self configBottomToolBar];
            [self configPlayerProgress];
            [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(pausePlayerAndShowNaviBar) name:AVPlayerItemDidPlayToEndTimeNotification object:self->_player.currentItem];
        });
    }];
}

/// Show slider
- (void)configPlayerProgress {
    if (_slider == nil) return;
    
    AVPlayerItem *playerItem = _player.currentItem;
    AVAssetTrack *track = [[playerItem.asset tracksWithMediaType:AVMediaTypeVideo] firstObject];
    if (track) _fps = track.nominalFrameRate;
    else _fps = 30;
    
    UISlider *slider = _slider;
    float total = roundf(CMTimeGetSeconds([playerItem.asset duration]));
    _playerDuration = total;
    _sliderCurrentTimeLabel.text = [self convertTime:0];
    _sliderTotalTimeLabel.text = [self convertTime:total];
    
    __weak typeof(self) weakSelf = self;
    [_player addPeriodicTimeObserverForInterval:CMTimeMake(1.0, 1.0) queue:dispatch_get_main_queue() usingBlock:^(CMTime time) {
        float current = roundf(CMTimeGetSeconds(time));
        weakSelf.playerCurrent = current;
        if (weakSelf.isSliding) return;
        weakSelf.sliderCurrentTimeLabel.text = [weakSelf convertTime:current];
        slider.value = current/total;
    }];
}

- (void)configPlayButton {
    _playButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [_playButton setImage:[UIImage tz_imageNamedFromMyBundle:@"MMVideoPreviewPlay"] forState:UIControlStateNormal];
    [_playButton setImage:[UIImage tz_imageNamedFromMyBundle:@"MMVideoPreviewPlayHL"] forState:UIControlStateHighlighted];
    [_playButton addTarget:self action:@selector(playButtonClick) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_playButton];
}

- (void)configSlider {
    UIColor *color = [[UIColor whiteColor] colorWithAlphaComponent:0.9];
    
    _slider = [[UISlider alloc] init];
    _slider.minimumValue = 0;
    _slider.maximumValue = 1;
    _slider.minimumTrackTintColor = color;
    _slider.maximumTrackTintColor = [UIColor lightGrayColor];
    [_slider setThumbImage:[UIImage tz_imageNamedFromMyBundle:@"photo_slider_thumb_icon"]
                  forState:UIControlStateNormal];
    
    [_slider addTarget:self action:@selector(sliderValueChanged:) forControlEvents:UIControlEventValueChanged];
    [_slider addTarget:self action:@selector(sliderTouchDown:) forControlEvents:UIControlEventTouchDown];
    [_slider addTarget:self action:@selector(sliderTouchUp:) forControlEvents:UIControlEventTouchUpInside];
    [_slider addTarget:self action:@selector(sliderTouchUp:) forControlEvents:UIControlEventTouchUpOutside];
    
    [_sliderToolBar addSubview:_slider];
    
    _sliderCurrentTimeLabel = [[UILabel alloc] init];
    _sliderCurrentTimeLabel.font = [UIFont systemFontOfSize:13];
    _sliderCurrentTimeLabel.textColor = color;
    _sliderCurrentTimeLabel.textAlignment = NSTextAlignmentLeft;
    [_sliderToolBar addSubview:_sliderCurrentTimeLabel];
    
    _sliderTotalTimeLabel = [[UILabel alloc] init];
    _sliderTotalTimeLabel.font = [UIFont systemFontOfSize:13];
    _sliderTotalTimeLabel.textColor = color;
    _sliderTotalTimeLabel.textAlignment = NSTextAlignmentLeft;
    [_sliderToolBar addSubview:_sliderTotalTimeLabel];
    
    _sliderPlayButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [_sliderPlayButton setImage:[UIImage tz_imageNamedFromMyBundle:@"photo_slider_video_play"] forState:UIControlStateNormal];
    [_sliderPlayButton setImage:[UIImage tz_imageNamedFromMyBundle:@"photo_slider_video_pause"] forState:UIControlStateSelected];
    [_sliderPlayButton addTarget:self action:@selector(sliderPlayButtonClick:) forControlEvents:UIControlEventTouchUpInside];
    [_sliderToolBar addSubview:_sliderPlayButton];
}

- (void)configBottomToolBar {
    _toolBar = [[UIView alloc] initWithFrame:CGRectZero];
    CGFloat rgb = 34 / 255.0;
    _toolBar.backgroundColor = [UIColor colorWithRed:rgb green:rgb blue:rgb alpha:0.7];
    
    _doneButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _doneButton.titleLabel.font = [UIFont systemFontOfSize:16];
    if (!_cover) {
        _doneButton.enabled = NO;
    }
    [_doneButton addTarget:self action:@selector(doneButtonClick) forControlEvents:UIControlEventTouchUpInside];
    TZImagePickerController *tzImagePickerVc = (TZImagePickerController *)self.navigationController;
    if (tzImagePickerVc) {
        [_doneButton setTitle:tzImagePickerVc.doneBtnTitleStr forState:UIControlStateNormal];
        [_doneButton setTitleColor:tzImagePickerVc.oKButtonTitleColorNormal forState:UIControlStateNormal];
    } else {
        [_doneButton setTitle:[NSBundle tz_localizedStringForKey:@"Done"] forState:UIControlStateNormal];
        [_doneButton setTitleColor:[UIColor colorWithRed:(83/255.0) green:(179/255.0) blue:(17/255.0) alpha:1.0] forState:UIControlStateNormal];
    }
    [_doneButton setTitleColor:tzImagePickerVc.oKButtonTitleColorDisabled forState:UIControlStateDisabled];
    [_toolBar addSubview:_doneButton];
    
    // 如果显示 播放进度条时，play 和 pause button，位置需要调整
    _showSlider = tzImagePickerVc.showVideoPlaySlider;
    if (_showSlider) {
        _touchScreen = [[UIControl alloc] init];
        [self.view insertSubview:_touchScreen belowSubview:_playButton];
        [_touchScreen addTarget:self action:@selector(controlToolBarShowOrHide:) forControlEvents:UIControlEventTouchUpInside];
        
        _sliderToolBar = [[UIView alloc] initWithFrame:CGRectZero];
        _sliderToolBar.backgroundColor = [UIColor colorWithRed:rgb green:rgb blue:rgb alpha:0.7];
        [self.view addSubview:_sliderToolBar];
        [self configSlider];
    }
    
    [self.view addSubview:_toolBar];
    
    if (tzImagePickerVc.videoPreviewPageUIConfigBlock) {
        tzImagePickerVc.videoPreviewPageUIConfigBlock(_playButton, _toolBar, _doneButton);
    }
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    TZImagePickerController *tzImagePicker = (TZImagePickerController *)self.navigationController;
    if (tzImagePicker && [tzImagePicker isKindOfClass:[TZImagePickerController class]]) {
        return tzImagePicker.statusBarStyle;
    }
    return [super preferredStatusBarStyle];
}

#pragma mark - Layout

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    
    BOOL isFullScreen = self.view.tz_height == [UIScreen mainScreen].bounds.size.height;
    CGFloat statusBarHeight = isFullScreen ? [TZCommonTools tz_statusBarHeight] : 0;
    CGFloat statusBarAndNaviBarHeight = statusBarHeight + self.navigationController.navigationBar.tz_height;
    _playerLayer.frame = self.view.bounds;
    CGFloat toolBarHeight = [TZCommonTools tz_isIPhoneX] ? 44 + (83 - 49) : 44;
    _toolBar.frame = CGRectMake(0, self.view.tz_height - toolBarHeight, self.view.tz_width, toolBarHeight);
    _doneButton.frame = CGRectMake(self.view.tz_width - 44 - 12, 0, 44, 44);
    
    CGRect tempRect = CGRectMake(0, statusBarAndNaviBarHeight, self.view.tz_width, self.view.tz_height - statusBarAndNaviBarHeight - toolBarHeight);
    if (_showSlider) {
        _touchScreen.frame = tempRect;
        _playButton.frame = CGRectMake(0, 0, 50, 50);
        _playButton.tz_centerX = self.view.center.x;
        _playButton.tz_centerY = self.view.center.y;
    }
    else {
        _playButton.frame = tempRect;
    }
    [self layoutSliderToolBarSubviews];
    
    TZImagePickerController *tzImagePickerVc = (TZImagePickerController *)self.navigationController;
    if (tzImagePickerVc.videoPreviewPageDidLayoutSubviewsBlock) {
        tzImagePickerVc.videoPreviewPageDidLayoutSubviewsBlock(_playButton, _toolBar, _doneButton);
    }
}

- (void)layoutSliderToolBarSubviews {
    CGFloat height = 30;
    CGFloat view_width = self.view.tz_width;
    _sliderToolBar.frame = CGRectMake(0, CGRectGetMinY(_toolBar.frame) - height, view_width, height);
    
    CGFloat buttonWidth = 40;
    _sliderPlayButton.frame = CGRectMake(0, 0, buttonWidth, height);
    
    CGFloat ctimeX = CGRectGetMaxX(_sliderPlayButton.frame);
    CGFloat timeWidth = 57;
    _sliderCurrentTimeLabel.frame = CGRectMake(ctimeX, 0, timeWidth, height);
    
    CGFloat ttimeX = view_width - timeWidth - 5;
    _sliderTotalTimeLabel.frame = CGRectMake(ttimeX, 0, timeWidth, height);
    
    CGFloat sliderX = CGRectGetMaxX(_sliderCurrentTimeLabel.frame) + 5;
    CGFloat sliderWidth = CGRectGetMinX(_sliderTotalTimeLabel.frame) - CGRectGetMaxX(_sliderCurrentTimeLabel.frame) - 10;
    _slider.frame = CGRectMake(sliderX, 0, sliderWidth, height);
    _slider.tz_centerY = height/2;
}

#pragma mark - Click Event

- (void)playButtonClick {
    if (_player.rate == 0.0f) {
        [self playPlayerAndHideNaviBar];
    }
    else if (!_showSlider) {
        [self pausePlayerAndShowNaviBar];
    }
}

- (void)doneButtonClick {
    if (self.navigationController) {
        TZImagePickerController *imagePickerVc = (TZImagePickerController *)self.navigationController;
        if (imagePickerVc.autoDismiss) {
            [self.navigationController dismissViewControllerAnimated:YES completion:^{
                [self callDelegateMethod];
            }];
        } else {
            [self callDelegateMethod];
        }
    } else {
        [self dismissViewControllerAnimated:YES completion:^{
            [self callDelegateMethod];
        }];
    }
}

- (void)callDelegateMethod {
    TZImagePickerController *imagePickerVc = (TZImagePickerController *)self.navigationController;
    if ([imagePickerVc.pickerDelegate respondsToSelector:@selector(imagePickerController:didFinishPickingVideo:sourceAssets:)]) {
        [imagePickerVc.pickerDelegate imagePickerController:imagePickerVc didFinishPickingVideo:_cover sourceAssets:_model.asset];
    }
    if (imagePickerVc.didFinishPickingVideoHandle) {
        imagePickerVc.didFinishPickingVideoHandle(_cover,_model.asset);
    }
}

- (void)controlToolBarShowOrHide:(id)obj {
    
    if ([obj isKindOfClass:[UIControl class]]) {
        _touchScreen.selected = !_touchScreen.isSelected;
    }
    else if ([obj isKindOfClass:[NSNumber class]]) {
        _touchScreen.selected = [(NSNumber *)obj boolValue];
    }
    
    if (_touchScreen.isSelected) {
        [self hideNaviBarAndTools];
    }
    else {
        [self showNaviBarAndTools];
    }
}

#pragma mark - slider action

- (void)sliderTouchDown:(UISlider *)slider {
    _isSliding = YES;
    if (_playerStatus == PlayerStatus_Play) {
        [_player pause];
    }
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
}

- (void)sliderTouchUp:(UISlider *)slider {
    _isSliding = NO;
    if (_playerStatus == PlayerStatus_Play) {
        [self playButtonClick];
    }
}

- (void)sliderValueChanged:(UISlider *)slider {
    float current = _playerDuration * slider.value;
    _sliderCurrentTimeLabel.text = [self convertTime:current];
    
    CMTime time = CMTimeMakeWithSeconds(current, _fps);
    [_player seekToTime:time toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
}

- (void)sliderPlayButtonClick:(UIButton *)button {
    button.selected = !button.isSelected;
    if (button.isSelected) {
        [self playPlayerAndHideNaviBar];
    }
    else {
        [self pausePlayerAndShowNaviBar];
    }
}

#pragma mark - Notification Method

- (void)playPlayerAndHideNaviBar {
    
    CMTime currentTime = _player.currentItem.currentTime;
    CMTime durationTime = _player.currentItem.duration;
    
    if (currentTime.value == durationTime.value) [_player.currentItem seekToTime:CMTimeMake(0, 1)];
    [_player play];
    [_playButton setImage:nil forState:UIControlStateNormal];
    [_playButton setImage:nil forState:UIControlStateHighlighted];

    _playerStatus = PlayerStatus_Play;
    if (_showSlider) {
        _sliderPlayButton.selected = YES;
        [self performSelector:@selector(controlToolBarShowOrHide:) withObject:@(YES) afterDelay:3];
    }
    else {
        [self hideNaviBarAndTools];
    }
}

- (void)pausePlayerAndShowNaviBar {
    [_player pause];
    [_playButton setImage:[UIImage tz_imageNamedFromMyBundle:@"MMVideoPreviewPlay"] forState:UIControlStateNormal];
    [_playButton setImage:[UIImage tz_imageNamedFromMyBundle:@"MMVideoPreviewPlayHL"] forState:UIControlStateHighlighted];

    _playerStatus = PlayerStatus_Pause;
    if (_showSlider) {
        _sliderPlayButton.selected = NO;
        [NSObject cancelPreviousPerformRequestsWithTarget:self];
    }
    
    [self showNaviBarAndTools];
}

- (void)hideNaviBarAndTools {
    if (_showSlider && (_playerDuration - _playerCurrent) < 3) return;
    
    _toolBar.hidden = YES;
    [UIApplication sharedApplication].statusBarHidden = YES;
    [self.navigationController setNavigationBarHidden:YES];
    if (_showSlider) {
        _sliderToolBar.hidden = YES;
    }
}

- (void)showNaviBarAndTools {
    _toolBar.hidden = NO;
    [self.navigationController setNavigationBarHidden:NO];
    
    if (self.needShowStatusBar) {
        [UIApplication sharedApplication].statusBarHidden = NO;
    }
    if (_showSlider) {
        _sliderToolBar.hidden = NO;
        if (_playerStatus == PlayerStatus_Play) {
            [self performSelector:@selector(controlToolBarShowOrHide:) withObject:@(YES) afterDelay:3];
        }
    }
}

#pragma mark - convert time
- (NSString *)convertTime:(int)time {
    int hours = time/3600;
    int minutes = time%3600/60;
    int seconds = time%60;
    
    NSString *hoursTime = @"";
    // 是否需要显示小时？
    if (hours > -10) hoursTime = [NSString stringWithFormat:@"%02d:", hours];

    return [NSString stringWithFormat:@"%@%02d:%02d", hoursTime, minutes, seconds];;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma clang diagnostic pop

@end
