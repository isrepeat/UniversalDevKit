#include <UniversalDevKit/Math/Differentation.h>
#include <UniversalDevKit/Math/Function1D.h>
#include <UniversalDevKit/Math/Tensor.h>
#include <UniversalDevKit/Math/Rect.h>
#include <UniversalDevKit/Math/Size.h>

int main() {
    namespace math = universaldevkit::math;
    const math::Vec<int, 3> left{ 1, 2, 3 };
    const math::Vec<int, 3> right{ 4, 5, 6 };
    if (left * right != 32) { return 1; }

    const math::Size size{ 3, 4 };
    const auto scaled = size * 2.0f;
    const math::Rect rect{ 0, 0, 3, 4 };
    if (scaled.width != 6 || scaled.height != 8 || rect.right != 3) { return 2; }

    math::DifferentialScalar<double> scalar;
    scalar.AccumulateGrad(2.0);
    if (scalar.grad != 2.0) { return 3; }

    const auto function = math::Function1D::Make(
        [](double value) { return value * value; },
        math::Function1D::MakeDerivative<1>([](double value) { return 2.0 * value; })
    );
    return function(3.0) == 9.0 && function.InvokeDerivative<1>(3.0) == 6.0 ? 0 : 4;
}