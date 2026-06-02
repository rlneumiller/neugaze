mod camera_view;
mod capture_dialog;
mod window;

use gtk4::prelude::*;
use tracing_subscriber::EnvFilter;
use zbus::blocking::{Connection as BlockingConnection, Proxy as BlockingProxy};

fn check_cpu_support() {
    #[cfg(target_arch = "x86_64")]
    {
        if !std::arch::is_x86_feature_detected!("avx") {
            eprintln!(
                "neugaze-gui requires an x86_64 CPU with AVX support.\n\
                The current host does not expose AVX, so the native image-processing path cannot run.\n\n\
                If you are on a virtual machine, enable AVX support for the guest.\n\
                If you are on real hardware, use a CPU with AVX or build the project with a narrower instruction set."
            );
            std::process::exit(1);
        }
    }
}

// There is no point in running the GUI if the daemon isn't running, since all it does is talk to the daemon. 
// So we check for that at startup and bail with an error if we can't connect to the daemon's DBus interface. 
// This is a better user experience than showing a blank window with no functionality and a bunch of errors in the logs.
fn ensure_daemon_running() -> Result<(), String> {
    let conn = BlockingConnection::system()
        .map_err(|err| format!("Failed to connect to system DBus: {}", err))?;

    let dbus = BlockingProxy::new(
        &conn,
        "org.freedesktop.DBus",
        "/org/freedesktop/DBus",
        "org.freedesktop.DBus",
    )
    .map_err(|err| {
        format!(
            "Failed to create a DBus proxy to org.freedesktop.DBus.\n\nUnderlying error: {}",
            err
        )
    })?;

    let has_owner: bool = dbus
        .call("NameHasOwner", &("com.example.Neugaze",))
        .map_err(|err| {
            format!(
                "Failed to query the system bus for neugazed daemon ownership.\n\nUnderlying error: {}",
                err
            )
        })?;

    if !has_owner {
        return Err(
            "neugaze-gui is not designed to run stand-alone; the neugazed daemon must be installed and running first.".to_string(),
        );
    }

    Ok(())
}

fn main() {
    check_cpu_support();

    tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("warn")),
        )
        .init();

    if let Err(err) = ensure_daemon_running() {
        eprintln!("{err}");
        std::process::exit(1);
    }

    let username = std::env::var("USER").unwrap_or_else(|_| "unknown".to_string());

    let app = libadwaita::Application::builder()
        .application_id("com.example.Neugaze")
        .build();

    app.connect_activate(move |app| {
        let provider = gtk4::CssProvider::new();
        provider.load_from_string(
            r#"
            .success { color: #2ec27e; }
            .error { color: #e01b24; }
            "#,
        );
        gtk4::style_context_add_provider_for_display(
            &gtk4::gdk::Display::default().unwrap(),
            &provider,
            gtk4::STYLE_PROVIDER_PRIORITY_APPLICATION,
        );

        window::build_window(app, &username);
    });

    app.run();
}
