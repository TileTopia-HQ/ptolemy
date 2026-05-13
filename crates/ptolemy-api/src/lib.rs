// This Source Code Form is subject to the terms of the GNU Affero General Public
// License, v. 3.0. If a copy of the AGPL was not distributed with this
// file, You can obtain one at https://gnu.org/licenses/agpl-3.0.html.

pub mod auth;
pub mod routes;
pub mod ws;

use axum::{middleware, Router};
use ptolemy_storage::PgStore;
use std::sync::Arc;
use tower_http::trace::TraceLayer;

pub use auth::{AuthConfig, Claims, Role, generate_token};
pub use ws::EventBus;

pub type AppState = Arc<PgStore>;

pub fn app(state: AppState) -> Router {
    let event_bus = Arc::new(EventBus::new(1024));

    Router::new()
        .nest("/api/v1", routes::v1_routes())
        .nest("/ws", ws::ws_routes(event_bus))
        .layer(middleware::from_fn(auth::auth_middleware))
        .layer(TraceLayer::new_for_http())
        .with_state(state)
}
