#include "ApplicationSession.h"

#include <utility>

namespace {{application}}::application::core {
    ApplicationSession::ApplicationSession(
        model::ApplicationStateDocument applicationStateDocument,
        ApplicationStateStore::DocumentSaveHandler documentSaveHandler
    )
        : ApplicationSessionBase(std::move(applicationStateDocument), std::move(documentSaveHandler)) {
    }
}