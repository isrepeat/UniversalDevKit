using System.Windows;
using System.Windows.Media.Animation;

namespace AndroidAppPreviewer {
    internal sealed class GridLengthAnimation : AnimationTimeline {
        public static readonly DependencyProperty FromProperty = DependencyProperty.Register(
            nameof(From),
            typeof(GridLength),
            typeof(GridLengthAnimation),
            new PropertyMetadata(new GridLength(0.0)));

        public static readonly DependencyProperty ToProperty = DependencyProperty.Register(
            nameof(To),
            typeof(GridLength),
            typeof(GridLengthAnimation),
            new PropertyMetadata(new GridLength(0.0)));

        public static readonly DependencyProperty EasingFunctionProperty = DependencyProperty.Register(
            nameof(EasingFunction),
            typeof(IEasingFunction),
            typeof(GridLengthAnimation));

        public GridLength From {
            get => (GridLength)this.GetValue(FromProperty);
            set => this.SetValue(FromProperty, value);
        }

        public GridLength To {
            get => (GridLength)this.GetValue(ToProperty);
            set => this.SetValue(ToProperty, value);
        }

        public IEasingFunction? EasingFunction {
            get => (IEasingFunction?)this.GetValue(EasingFunctionProperty);
            set => this.SetValue(EasingFunctionProperty, value);
        }

        public override Type TargetPropertyType => typeof(GridLength);

        public override object GetCurrentValue(
            object defaultOriginValue,
            object defaultDestinationValue,
            AnimationClock animationClock) {
            var progress = animationClock.CurrentProgress ?? 0.0;
            progress = this.EasingFunction?.Ease(progress) ?? progress;
            var value = this.From.Value + (this.To.Value - this.From.Value) * progress;
            return new GridLength(value, GridUnitType.Pixel);
        }

        protected override Freezable CreateInstanceCore() {
            return new GridLengthAnimation();
        }
    }
}