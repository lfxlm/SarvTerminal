//! Custom tab bar with horizontal scrolling support for when there are many tabs.
//! Replaces Adw.TabBar with a custom implementation that uses GtkScrolledWindow
//! and arrow buttons for navigation.

const std = @import("std");
const adw = @import("adw");
const gobject = @import("gobject");
const gtk = @import("gtk");

const gresource = @import("../build/gresource.zig");
const Common = @import("../class.zig").Common;

pub const GhosttyTabBar = extern struct {
    const Self = @This();
    parent_instance: Parent,
    arrow_left: *gtk.Button,
    arrow_right: *gtk.Button,
    scroll_area: *gtk.ScrolledWindow,
    tab_strip: *gtk.Box,
    tab_view: ?*adw.TabView = null,
    pub const Parent = gtk.Bin;
    pub const getGObjectType = gobject.ext.defineClass(Self, .{
        .name = "GhosttyTabBar",
        .instanceInit = &init,
        .classInit = &Class.init,
        .parent_class = &Class.parent,
    });

    fn init(self: *Self, _: *Class) callconv(.c) void {
        gtk.Widget.initTemplate(self.as(gtk.Widget));
    }

    const C = Common(Self, null);
    pub const as = C.as;
    pub const ref = C.ref;
    pub const unref = C.unref;

    pub const Class = extern struct {
        parent_class: Parent.Class,
        var parent: *Parent.Class = undefined;
        pub const Instance = GhosttyTabBar;

        fn init(class: *Class) callconv(.c) void {
            gtk.Widget.Class.setTemplateFromResource(
                class.as(gtk.Widget.Class),
                gresource.blueprint(.{
                    .major = 1,
                    .minor = 5,
                    .name = "ghostty-tab-bar",
                }),
            );
        }

        pub const as = C.Class.as;
    };

    pub fn setTabView(self: *Self, tab_view: ?*adw.TabView) void {
        const tb = self;
        if (tb.tab_view) |old_tv| {
            _ = gobject.signalHandlersDisconnectMatched(
                old_tv, .{ .data = true }, 0, 0, null, null, tb,
            );
        }
        tb.tab_view = tab_view;
        if (tab_view) |tv| {
            _ = adw.TabView.signals.pageAttached.connect(tv, @TypeOf(tb), staticOnPageAttached, tb, .{});
            _ = adw.TabView.signals.pageDetached.connect(tv, @TypeOf(tb), staticOnPageDetached, tb, .{});
            _ = gobject.Object.signals.notify.connect(tv, @TypeOf(tb), staticOnNotifySelectedPage, tb, .{ .detail = "selected-page" });
            _ = gobject.Object.signals.notify.connect(tv, @TypeOf(tb), staticOnNotifyNPages, tb, .{ .detail = "n-pages" });
            syncTabButtons(tb);
            updateArrowVisibility(tb);
        }
    }

    pub fn getTabView(self: *Self) ?*adw.TabView {
        return self.tab_view;
    }

    const staticOnPageAttached = struct {
        fn call(tv: *adw.TabView, page: *adw.TabPage, position: c_int, tb: *GhosttyTabBar) callconv(.c) void {
            onPageAttached(tv, page, position, tb);
        }
    }.call;

    const staticOnPageDetached = struct {
        fn call(tv: *adw.TabView, page: *adw.TabPage, position: c_int, tb: *GhosttyTabBar) callconv(.c) void {
            onPageDetached(tv, page, position, tb);
        }
    }.call;

    const staticOnNotifySelectedPage = struct {
        fn call(obj: *gobject.Object, param: *gobject.ParamSpec, tb: *GhosttyTabBar) callconv(.c) void {
            onNotifySelectedPage(obj, param, tb);
        }
    }.call;

    const staticOnNotifyNPages = struct {
        fn call(obj: *gobject.Object, param: *gobject.ParamSpec, tb: *GhosttyTabBar) callconv(.c) void {
            onNotifyNPages(obj, param, tb);
        }
    }.call;

    fn onPageAttached(_: *adw.TabView, page: *adw.TabPage, position: c_int, self: *Self) callconv(.c) void {
        const tb = self;
        const child = page.getChild();
        const tab_btn = createTabButton(tb, page, child);
        tb.tab_strip.insert(tab_btn.as(gtk.Widget), position);
        tab_btn.show();
        updateArrowVisibility(tb);
    }

    fn onPageDetached(_: *adw.TabView, page: *adw.TabPage, _: c_int, self: *Self) callconv(.c) void {
        const tb = self;
        var it = tb.tab_strip.getFirstChild();
        while (it.as(gtk.Widget).getParent() != null) {
            const next = it.getNextSibling();
            const btn = it.as(gtk.Button);
            const stored_page: *adw.TabPage = @ptrFromInt(gobject.Object.getUserData(btn.as(gobject.Object)));
            if (stored_page == page) {
                tb.tab_strip.remove(it.as(gtk.Widget));
                gobject.Object.setUserData(btn.as(gobject.Object), null);
                break;
            }
            it = next orelse break;
        }
        updateArrowVisibility(tb);
    }

    fn onNotifySelectedPage(_: *gobject.Object, _: *gobject.ParamSpec, self: *Self) callconv(.c) void {
        const tb = self;
        if (tb.tab_view) |tv| {
            const selected = tv.getSelectedPage() orelse return;
            scrollToTabVisible(tb, selected);
        }
    }

    fn onNotifyNPages(_: *gobject.Object, _: *gobject.ParamSpec, self: *Self) callconv(.c) void {
        const tb = self;
        updateArrowVisibility(tb);
    }

    pub fn arrowLeftClicked(self: *Self) callconv(.c) void {
        const tb = self;
        if (tb.tab_view) |tv| {
            tv.selectPreviousPage();
        }
    }

    pub fn arrowRightClicked(self: *Self) callconv(.c) void {
        const tb = self;
        if (tb.tab_view) |tv| {
            tv.selectNextPage();
        }
    }

    fn syncTabButtons(self: *Self) void {
        const tb = self;
        const tv = tb.tab_view orelse return;
        var it = tb.tab_strip.getFirstChild();
        while (it.as(gtk.Widget).getParent() != null) {
            const next = it.getNextSibling();
            const btn = it.as(gtk.Button);
            gobject.Object.setUserData(btn.as(gobject.Object), null);
            tb.tab_strip.remove(it.as(gtk.Widget));
            it = next orelse break;
        }
        const n = tv.getNPages();
        var i: c_int = 0;
        while (i < n) : (i += 1) {
            const page = tv.getNthPage(i);
            const child = page.getChild();
            const tab_btn = createTabButton(tb, page, child);
            tb.tab_strip.append(tab_btn.as(gtk.Widget));
            tab_btn.show();
        }
    }

    fn createTabButton(_: *Self, page: *adw.TabPage, child: *gtk.Widget) *gtk.Button {
        const btn = gtk.Button.new() catch unreachable;
        btn.setCanFocus(false);
        btn.setFocusOnClick(false);
        btn.addStyleClass("ghostty-tab-button");
        const page_int: usize = @intFromPtr(page);
        gobject.Object.setUserData(btn.as(gobject.Object), @ptrFromInt(page_int));
        const title_obj = child.as(gobject.Object);
        const label = gtk.Label.new(null);
        label.addStyleClass("ghostty-tab-label");
        btn.setChild(label.as(gtk.Widget));
        _ = title_obj.bindProperty("title", label.as(gobject.Object), "label", .{ .sync_create = true });
        _ = gtk.Widget.signals.clicked.connect(btn, @TypeOf(btn), staticTabButtonClicked, btn, .{});
        return btn;
    }

    const staticTabButtonClicked = struct {
        fn call(widget: *gtk.Widget, btn: *gtk.Button) callconv(.c) void {
            tabButtonClicked(widget, btn);
        }
    }.call;

    fn tabButtonClicked(widget: *gtk.Widget, btn: *gtk.Button) void {
        _ = widget;
        const page_int: usize = @intFromPtr(gobject.Object.getUserData(btn.as(gobject.Object)));
        const page: *adw.TabPage = @ptrFromInt(page_int);
        var ancestor = btn.as(gtk.Widget).getParent();
        while (ancestor != null) {
            const tv = ancestor.as(adw.TabView);
            if (tv != null) {
                tv.setSelectedPage(page);
                return;
            }
            ancestor = ancestor.getParent();
        }
    }

    fn scrollToTabVisible(self: *Self, page: *adw.TabPage) void {
        const tb = self;
        var it = tb.tab_strip.getFirstChild();
        var target_btn: ?*gtk.Button = null;
        while (it.as(gtk.Widget).getParent() != null) {
            const next = it.getNextSibling();
            const btn = it.as(gtk.Button);
            const stored_page_int: usize = @intFromPtr(gobject.Object.getUserData(btn.as(gobject.Object)));
            const stored_page: *adw.TabPage = @ptrFromInt(stored_page_int);
            if (stored_page == page) {
                target_btn = btn;
                break;
            }
            it = next orelse break;
        }
        const btn = target_btn orelse return;
        const allocation = gtk.Widget.getAllocation(btn.as(gtk.Widget));
        const x = allocation.x;
        const width = allocation.width;
        const viewport = tb.scroll_area.getViewport() orelse return;
        const hadj = viewport.getHAdjustment() orelse return;
        const upper = gtk.Adjustment.getUpper(hadj);
        const page_val = gtk.Adjustment.getPage(hadj);
        const view_width = upper - page_val;
        const current_pos = gtk.Adjustment.getValue(hadj);
        const tab_right = x + width;
        if (x >= current_pos and tab_right <= current_pos + view_width) {
            return;
        }
        const half_width: usize = @intCast(view_width / 2);
        const offset: usize = @max(@as(usize, 0), x - half_width);
        const new_pos: f64 = @floatFromInt(offset);
        gtk.Adjustment.setValue(hadj, new_pos, false);
    }

    fn updateArrowVisibility(self: *Self) void {
        const tb = self;
        const tv = tb.tab_view orelse return;
        const n = tv.getNPages();
        if (n <= 1) {
            tb.arrow_left.hide();
            tb.arrow_right.hide();
            return;
        }
        const idle_data = struct {
            fn run(self_bar: *GhosttyTabBar) callconv(.c) bool {
                const allocation = gtk.Widget.getAllocation(self_bar.tab_strip.as(gtk.Widget));
                const scroll_width = self_bar.scroll_area.getAllocation().width;
                if (allocation.width > scroll_width) {
                    self_bar.arrow_left.show();
                    self_bar.arrow_right.show();
                } else {
                    self_bar.arrow_left.hide();
                    self_bar.arrow_right.hide();
                }
                return false;
            }
        }.run;
        const idle_cb: gtk.Callback = @ptrCast(@alignCast(idle_data));
        const idle_data_ptr: ?*anyopaque = @ptrFromInt(@intFromPtr(tb));
        _ = gtk.glib.idleAdd(idle_cb, idle_data_ptr, false);
    }
};
