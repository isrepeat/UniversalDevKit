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
        // Обычный документ сначала записывается через handler; при ошибке текущее
        // состояние в памяти не меняется и UI не видит несохранённые данные.
#if defined(ANDROID_APP_PREVIEWER)
        // Документ сценария живёт только в памяти preview-сеанса. Изменения UI
        // применяются к нему, но не затрагивают постоянный storage до экспорта.
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
        // Замена полного документа переводит storage в memory-only режим preview.
        *this->applicationStateDocument = std::move(applicationStateDocument);
        this->preview_isUsingPreviewSessionDocument = true;
    }

    bool ApplicationStateStore::preview_SaveSessionDocumentToPersistentStorage() {
        // Повторный экспорт обычного документа не требуется.
        if (!this->preview_isUsingPreviewSessionDocument) {
            return true;
        }
        // Только успешная запись завершает preview-режим; иначе пользователь может
        // повторить экспорт, не теряя изменений текущего сеанса.
        if (this->documentSaveHandler && !this->documentSaveHandler(*this->applicationStateDocument)) {
            return false;
        }
        this->preview_isUsingPreviewSessionDocument = false;
        return true;
    }
#endif
}