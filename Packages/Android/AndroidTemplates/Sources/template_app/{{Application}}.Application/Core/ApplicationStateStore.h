#pragma once
#include "../Model/ApplicationStateDocument.h"

#include <functional>
#include <memory>

namespace {{application}}::application::model {
    struct ApplicationStateDocument;
}

namespace {{application}}::application::core {
    class ApplicationStateStore final {
    public:
        using DocumentSaveHandler = std::function<bool(const model::ApplicationStateDocument&)>;

        explicit ApplicationStateStore(model::ApplicationStateDocument applicationStateDocument, DocumentSaveHandler documentSaveHandler = {});
        ~ApplicationStateStore() = default;

        ApplicationStateStore(const ApplicationStateStore&) = delete;
        ApplicationStateStore& operator=(const ApplicationStateStore&) = delete;

        const model::ApplicationStateDocument& CurrentDocument() const;
        bool TrySaveDocument(model::ApplicationStateDocument applicationStateDocument);
#if defined(ANDROID_APP_PREVIEWER)
        void preview_LoadSessionDocument(model::ApplicationStateDocument applicationStateDocument);
        bool preview_SaveSessionDocumentToPersistentStorage();
#endif

    private:
        std::unique_ptr<model::ApplicationStateDocument> applicationStateDocument;
        DocumentSaveHandler documentSaveHandler;
#if defined(ANDROID_APP_PREVIEWER)
        bool preview_isUsingPreviewSessionDocument = false;
#endif
    };
}