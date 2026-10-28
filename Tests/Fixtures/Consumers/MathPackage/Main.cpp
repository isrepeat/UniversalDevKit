#include <UniversalDevKit/Helpers/Math/Differentiation.h>
#include <UniversalDevKit/Helpers/Math/Function1D.h>
#include <UniversalDevKit/Helpers/Math/Tensor.h>
#include <UniversalDevKit/Helpers/Math/Rect.h>
#include <UniversalDevKit/Helpers/Math/Size.h>

#include <type_traits>
#include <utility>

namespace math = universaldevkit::helpers::math;

static_assert(std::is_same_v<decltype(std::declval<math::Mat<int, 2, 3>&>()[0][0]), int&>);
static_assert(std::is_same_v<decltype(std::declval<const math::Mat<int, 2, 3>&>()[0][0]), const int&>);
static_assert(std::is_same_v<decltype(std::declval<math::Tensor<int, 2, 3, 4>&>()[0][0][0]), int&>);
static_assert(std::is_same_v<decltype(std::declval<const math::Tensor<int, 2, 3, 4>&>()[0][0][0]), const int&>);
static_assert(std::is_same_v<math::Vec2f::value_type, float>);
static_assert(std::is_same_v<math::Vec3f::value_type, float>);
static_assert(std::is_same_v<math::Vec4f::value_type, float>);
static_assert(std::is_same_v<math::Mat1x1f::value_type, float>);
static_assert(std::is_same_v<math::Mat2x2f::value_type, float>);
static_assert(std::is_same_v<math::Mat3x3f::value_type, float>);
static_assert(std::is_same_v<math::Mat4x4f::value_type, float>);
static_assert(std::is_same_v<math::Vec3d::value_type, double>);
static_assert(std::is_same_v<math::Mat4x4d::value_type, double>);

constexpr bool CheckIndexing() {
    math::Mat<int, 2, 3> matrix;
    matrix[1][2] = 42;
    matrix[1][2] += 1;
    math::Tensor<int, 2, 3, 4> tensor;
    tensor[1][2][3] = 7;
    const auto& constant = tensor;
    return matrix.Data()[5] == 43 && constant[1][2][3] == 7 &&
        &constant[1][2][3] == tensor.Data() + 23;
}

static_assert(CheckIndexing());

int main() {
    namespace math = universaldevkit::helpers::math;
    const math::Vec<int, 3> left{ 1, 2, 3 };
    const math::Vec<int, 3> right{ 4, 5, 6 };
    if (left * right != 32) { return 1; }

    const math::Size size{ 3, 4 };
    const auto scaled = size * 2.0f;
    const math::Rect rect{ 0, 0, 3, 4 };
    if (scaled.width != 6 || scaled.height != 8 || rect.right != 3) { return 2; }
    const auto convertedSize = static_cast<math::Size_f>(size);
    const auto convertedRect = static_cast<math::Rect_f>(rect);
    if (convertedSize.width != 3.0f || convertedRect.bottom != 4.0f || !CheckIndexing()) { return 5; }

    math::DifferentialScalar<double> scalar;
    scalar.AccumulateGrad(2.0);
    if (scalar.grad != 2.0) { return 3; }
    scalar.value = 3.0;
    scalar.ResetGrad();
    if (scalar.value != 3.0 || scalar.grad != 0.0) { return 6; }
    scalar.Reset();
    if (scalar.value != 0.0) { return 7; }
    math::DifferentialVector<float, 2> gradient;
    gradient.AccumulateGrad(math::Vec<float, 2>{ 1.0f, 2.0f });
    gradient.AccumulateGrad(math::Vec<float, 2>{ 3.0f, 4.0f });
    if (gradient.grad[0] != 4.0f || gradient.grad[1] != 6.0f) { return 8; }
    gradient.ResetGrad();
    if (gradient.grad[0] != 0.0f || gradient.grad[1] != 0.0f) { return 9; }

    const auto function = math::Function1D::Make(
        [](double value) { return value * value; },
        math::Function1D::MakeDerivative<1>([](double value) { return 2.0 * value; }),
        math::Function1D::MakePrimitive<1>([](double value) { return value * value * value / 3.0; })
    );
    return function(3.0) == 9.0 && function.InvokeDerivative<1>(3.0) == 6.0 &&
        function.InvokePrimitive<1>(3.0) == 9.0 ? 0 : 4;
}