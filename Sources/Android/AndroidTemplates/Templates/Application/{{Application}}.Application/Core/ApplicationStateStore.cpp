#include "ApplicationStateStore.h"

#include "../Model/ApplicationStateDocument.h"

#include <utility>

namespace {{application}}::application::core {
    ApplicationStateStore::ApplicationStateStore(model::ApplicationStateDocument applicationStateDocument, DocumentSaveHandler documentSaveHandler)
        : applicationStateDocument(std::make_unique<model::ApplicationStateDocument>(std::move(applicationStateDocument)))
        , documentSaveHandler(std::move(documentSaveHandler)) {
    }


    //
    // API
    //
    const model::ApplicationStateDocument& ApplicationStateStore::CurrentDocument() const {
        return *this->applicationStateDocument;
    }

    bool ApplicationStateStore::TrySaveDocument(model::ApplicationStateDocument applicationStateDocument) {
        // Write a regular document through the handler first. On failure,
        // retain the in-memory state and keep unsaved data out of the UI.
#if defined(ANDROID_APP_PREVIEWER)
        // A scenario document lives in preview session memory. UI edits
        // stay out of persistent storage until export.
        if (!this->preview_isUsingPreviewSessionDocument && this->documentSaveHandler && !this->documentSaveHandler(applicationStateDocument)) {
#else
        if (this->documentSaveHandler && !this->documentSaveHandler(applicationStateDocument)) {
#endif
            return false;
        }
        *this->applicationStateDocument = std::move(applicationStateDocument);
        return true;
    }

#if defined(ANDROID_APP_PREVIEWER)
    void ApplicationStateStore::preview_LoadSessionDocument(model::ApplicationStateDocument applicationStateDocument) {
        // Replacing the entire document switches storage to memory-only preview mode.
        *this->applicationStateDocument = std::move(applicationStateDocument);
        this->preview_isUsingPreviewSessionDocument = true;
    }

    bool ApplicationStateStore::preview_SaveSessionDocumentToPersistentStorage() {
        // A regular document needs no second export.
        if (!this->preview_isUsingPreviewSessionDocument) {
            return true;
        }
        // End preview mode only after a successful write so the user can
        // retry export without losing current session changes.
        if (this->documentSaveHandler && !this->documentSaveHandler(*this->applicationStateDocument)) {
            return false;
        }
        this->preview_isUsingPreviewSessionDocument = false;
        return true;
    }
#endif
}