#pragma once

namespace universaldevkit::meta {
    template<typename T>
    struct ExtractUnderlyingType {
        using type = T;
    };

    template<template<typename, typename...> typename Container, typename T, typename... TArguments>
    struct ExtractUnderlyingType<Container<T, TArguments...>> {
        using type = T;
    };

    template<typename T>
    using ExtractUnderlyingType_t = typename ExtractUnderlyingType<T>::type;
}