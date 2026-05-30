use tauri::menu::{MenuBuilder, SubmenuBuilder, MenuItemBuilder};

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
  tauri::Builder::default()
    .setup(|app| {
      if cfg!(debug_assertions) {
        app.handle().plugin(
          tauri_plugin_log::Builder::default()
            .level(log::LevelFilter::Info)
            .build(),
        )?;
      }

      let handle = app.handle().clone();
      let menu = MenuBuilder::new(&handle)
        .item(
          &SubmenuBuilder::new(&handle, "File")
            .item(&MenuItemBuilder::new("New Invoice").id("new_invoice").build(&handle)?)
            .item(&MenuItemBuilder::new("Open").id("open").build(&handle)?)
            .separator()
            .item(&MenuItemBuilder::new("Save").id("save").accelerator("CmdOrCtrl+S").build(&handle)?)
            .separator()
            .item(&MenuItemBuilder::new("Exit").id("exit").build(&handle)?)
            .build()?,
        )
        .item(
          &SubmenuBuilder::new(&handle, "Edit")
            .item(&MenuItemBuilder::new("Undo").id("undo").accelerator("CmdOrCtrl+Z").build(&handle)?)
            .item(&MenuItemBuilder::new("Redo").id("redo").accelerator("CmdOrCtrl+Shift+Z").build(&handle)?)
            .separator()
            .item(&MenuItemBuilder::new("Cut").id("cut").accelerator("CmdOrCtrl+X").build(&handle)?)
            .item(&MenuItemBuilder::new("Copy").id("copy").accelerator("CmdOrCtrl+C").build(&handle)?)
            .item(&MenuItemBuilder::new("Paste").id("paste").accelerator("CmdOrCtrl+V").build(&handle)?)
            .build()?,
        )
        .item(
          &SubmenuBuilder::new(&handle, "View")
            .item(&MenuItemBuilder::new("Refresh").id("refresh").accelerator("F5").build(&handle)?)
            .item(&MenuItemBuilder::new("Search").id("search").accelerator("CmdOrCtrl+F").build(&handle)?)
            .build()?,
        )
        .item(
          &SubmenuBuilder::new(&handle, "Help")
            .item(&MenuItemBuilder::new("About ApexBooks").id("about").build(&handle)?)
            .item(&MenuItemBuilder::new("Documentation").id("docs").build(&handle)?)
            .build()?,
        )
        .build()?;
      app.set_menu(menu)?;
      Ok(())
    })
    .run(tauri::generate_context!())
    .expect("error while running tauri application");
}
