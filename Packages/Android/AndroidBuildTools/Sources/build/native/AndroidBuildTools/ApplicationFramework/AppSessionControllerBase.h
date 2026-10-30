#pragma once
#include <functional>
#include <utility>
#include <string>

namespace application_framework {
    template <typename THostCommandDispatcher, typename THostCommand, typename THostCommandData>
    class AppSessionControllerBase : public THostCommandDispatcher {
    public:
        using HostEventHandler = std::function<void(THostCommand, const THostCommandData&)>;
        AppSessionControllerBase() = default;
        virtual ~AppSessionControllerBase() = default;

        //
        // IHostCommandDispatcher
        //
        void Dispatch(THostCommand hostCommand, const THostCommandData& hostCommandData = {}) override;

        void SetHostEventHandler(HostEventHandler hostEventHandler);
        const std::string& Status() const;
        void SetStatus(std::string value);

    protected:
        virtual void OnUnhandledHostCommand(THostCommand, const THostCommandData&) {
        }

    private:
        HostEventHandler hostEventHandler;
        std::string status;
    };
}

namespace application_framework {
    //
    // IHostCommandDispatcher
    //
    template <typename THostCommandDispatcher, typename THostCommand, typename THostCommandData>
    void AppSessionControllerBase<THostCommandDispatcher, THostCommand, THostCommandData>::Dispatch(
        THostCommand hostCommand,
        const THostCommandData& hostCommandData
    ) {
        if (this->hostEventHandler) {
            this->hostEventHandler(hostCommand, hostCommandData);
        } else {
            this->OnUnhandledHostCommand(hostCommand, hostCommandData);
        }
    }

    //
    // API
    //
    template <typename THostCommandDispatcher, typename THostCommand, typename THostCommandData>
    void AppSessionControllerBase<THostCommandDispatcher, THostCommand, THostCommandData>::SetHostEventHandler(HostEventHandler hostEventHandler) {
        this->hostEventHandler = std::move(hostEventHandler);
    }

    template <typename THostCommandDispatcher, typename THostCommand, typename THostCommandData>
    const std::string& AppSessionControllerBase<THostCommandDispatcher, THostCommand, THostCommandData>::Status() const {
        return this->status;
    }

    template <typename THostCommandDispatcher, typename THostCommand, typename THostCommandData>
    void AppSessionControllerBase<THostCommandDispatcher, THostCommand, THostCommandData>::SetStatus(std::string value) {
        this->status = std::move(value);
    }
}