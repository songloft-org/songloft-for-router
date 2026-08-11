<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
<meta http-equiv="X-UA-Compatible" content="IE=Edge"/>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
<meta HTTP-EQUIV="Pragma" CONTENT="no-cache"/>
<meta HTTP-EQUIV="Expires" CONTENT="-1"/>
<link rel="shortcut icon" href="images/favicon.png"/>
<link rel="icon" href="images/favicon.png"/>
<title>软件中心 - SongLoft</title>
<link rel="stylesheet" type="text/css" href="index_style.css"/>
<link rel="stylesheet" type="text/css" href="form_style.css"/>
<link rel="stylesheet" type="text/css" href="css/element.css">
<link rel="stylesheet" type="text/css" href="res/softcenter.css">
<script type="text/javascript" src="/js/jquery.js"></script>
<script type="text/javascript" src="/state.js"></script>
<script type="text/javascript" src="/help.js"></script>
<script type="text/javascript" src="/general.js"></script>
<script type="text/javascript" src="/popup.js"></script>
<script type="text/javascript" src="/res/softcenter.js"></script>
<style>
        input:focus { outline: none; }
        .button_gen { width: auto !important; padding: 4px 10px; display: inline-block !important; }
        .button_gen:disabled { opacity: .35; cursor: not-allowed; }
        #log_text { width: 100% !important; box-sizing: border-box !important; }
        .songloft_mask {
                position: fixed;
                top: 0; left: 0;
                width: 100%; height: 100%;
                z-index: 9998;
                display: none;
                background: rgba(0,0,0,0.55);
        }
        .songloft_popup {
                position: fixed;
                z-index: 9999;
                top: 260px;
                left: calc(50% + 97px);
                transform: translateX(-50%);
                width: 780px;
                background: #000;
                border-radius: 10px;
                box-shadow: 3px 3px 10px #000;
                display: none;
        }
        .songloft_popup_head { padding: 10px 12px; font-size: 16px; font-weight: 700; color: #99FF00; text-align: center; }
        .songloft_popup_body { padding: 0 12px 12px 12px; }
        #log_text { background: #000 !important; color: #fff !important; border: 1px solid #111 !important; }
        .songloft_btn {
                border: 1px solid #222;
                background: linear-gradient(to bottom, #003333 0%, #000000 100%);
                font-size: 10pt;
                color: #fff;
                padding: 5px 10px;
                border-radius: 5px;
                cursor: pointer;
                display: none;
                margin-left: 10px;
        }
        .songloft_btn:hover {
                border: 1px solid #222;
                background: linear-gradient(to bottom, #27c9c9 0%, #279fd9 100%);
                color: #fff;
        }
</style>
<script>
var dbus = {};
var logTimer = null;
var logAutoScroll = true;
var logIgnoreScroll = false;
var logTrimming = false;
var statusTimer = null;

function menu_hook(title, tab) {
        tabtitle[tabtitle.length - 1] = new Array("", "songloft");
        tablink[tablink.length - 1] = new Array("", "Module_songloft.asp");
}

function init() {
        show_menu(menu_hook);
        get_dbus_data();
        buildswitch();
        $("#log_text").on("scroll", function(){
                if (logIgnoreScroll) return;
                var el = this;
                logAutoScroll = (el.scrollHeight - (el.scrollTop + el.clientHeight) < 20);
        });
}

function E(id){ return document.getElementById(id); }

function buildswitch() {
        $("#songloft_enable").click(function(){
                update_visibility();
        });
}

function get_dbus_data() {
        $.ajax({
                type: "GET",
                url: "/_api/songloft",
                dataType: "json",
                async: true,
                cache: false,
                success: function(data) {
                        dbus = (data.result && data.result[0]) ? data.result[0] : {};
                        if (dbus["songloft_version"]) {
                                $("#songloft_version").html("当前版本：" + dbus["songloft_version"]);
                        }
                        fill_form();
                        update_visibility();
                        check_status();
                }
        });
}

function fill_form() {
        E("songloft_enable").checked = (dbus["songloft_enable"] == "1");
        E("songloft_listen_port").value = (dbus["songloft_listen_port"] && dbus["songloft_listen_port"] != "null")
                ? dbus["songloft_listen_port"] : "58091";
        E("songloft_db_path").value = (dbus["songloft_db_path"] && dbus["songloft_db_path"] != "null")
                ? dbus["songloft_db_path"] : "";
        E("songloft_base_path").value = (dbus["songloft_base_path"] && dbus["songloft_base_path"] != "null")
                ? dbus["songloft_base_path"] : "";
        E("songloft_admin_username").value = (dbus["songloft_admin_username"] && dbus["songloft_admin_username"] != "null")
                ? dbus["songloft_admin_username"] : "";
        E("songloft_admin_password").value = (dbus["songloft_admin_password"] && dbus["songloft_admin_password"] != "null")
                ? dbus["songloft_admin_password"] : "";
        E("songloft_bin_path").value = (dbus["songloft_bin_path"] && dbus["songloft_bin_path"] != "null")
                ? dbus["songloft_bin_path"] : "";
}

function update_visibility() {
        var enabled = E("songloft_enable").checked;
        var display = enabled ? "" : "none";
        E("tr_status").style.display    = display;
        E("tr_port").style.display      = display;
        E("tr_db_path").style.display   = display;
        E("tr_username").style.display  = display;
        E("tr_password").style.display  = display;
        E("tr_base_path").style.display = display;
        E("tr_bin_path").style.display  = display;
}

function apply_config() {
        var enable = E("songloft_enable").checked ? "1" : "0";
        var port = $.trim(E("songloft_listen_port").value || "");
        var dbPath = $.trim(E("songloft_db_path").value || "");
        var basePath = $.trim(E("songloft_base_path").value || "");
        var username = $.trim(E("songloft_admin_username").value || "");
        var password = $.trim(E("songloft_admin_password").value || "");
        var binPath = $.trim(E("songloft_bin_path").value || "");

        if (enable == "1") {
                if (!port) { alert("监听端口不能为空！"); return; }
                if (isNaN(parseInt(port, 10)) || parseInt(port, 10) <= 0 || parseInt(port, 10) > 65535) {
                        alert("监听端口必须是 1~65535 之间的数字！"); return;
                }
                if (!dbPath) { alert("根目录不能为空！"); return; }
        }

        var fields = {};
        fields["songloft_enable"]         = enable;
        fields["songloft_listen_port"]    = port;
        fields["songloft_db_path"]        = dbPath;
        fields["songloft_base_path"]      = basePath;
        fields["songloft_admin_username"] = username;
        fields["songloft_admin_password"] = password;
        fields["songloft_bin_path"]       = binPath;

        E("btn_apply").disabled = true;
        var id = parseInt(Math.random() * 100000000);
        var action = (enable == "1") ? 1 : 2;
        var postData = {"id": id, "method": "songloft_config.sh", "params": [action], "fields": fields};
        $.ajax({
                type: "POST",
                url: "/_api/",
                data: JSON.stringify(postData),
                dataType: "json",
                success: function() {
                        setTimeout(function(){
                                get_dbus_data();
                                setTimeout(function(){ E("btn_apply").disabled = false; }, 800);
                        }, 500);
                },
                error: function() {
                        E("btn_apply").disabled = false;
                }
        });
}

function clear_log() {
        var id = parseInt(Math.random() * 100000000);
        var postData = {"id": id, "method": "songloft_config.sh", "params": [3], "fields": {}};
        $.ajax({type:"POST", url:"/_api/", data: JSON.stringify(postData), dataType:"json",
                success:function(){ setTimeout("get_log();", 200); }});
}

function open_log_popup() {
        logAutoScroll = true;
        $("#songloft_log_mask").fadeIn(100);
        $("#songloft_log_popup").fadeIn(150);
        get_log(1);
}

function close_log_popup() {
        stop_log_poll();
        $("#songloft_log_popup").fadeOut(120);
        $("#songloft_log_mask").fadeOut(120);
}

function stop_log_poll() {
        if (logTimer) { clearTimeout(logTimer); logTimer = null; }
}

function get_log(action) {
        if (action) stop_log_poll();
        $.ajax({
                url: "/_temp/songloft.log",
                type: "GET",
                cache: false,
                dataType: "text",
                success: function(response){
                        var el = E("log_text");
                        var prevTop = el.scrollTop;
                        logIgnoreScroll = true;
                        el.value = response || "";
                        if (logAutoScroll) { el.scrollTop = el.scrollHeight; } else { el.scrollTop = prevTop; }
                        logIgnoreScroll = false;
                        if (!logTrimming) {
                                var lines = (el.value ? el.value.split("\n").length : 0);
                                if (lines > 500) {
                                        logTrimming = true;
                                        var id = parseInt(Math.random() * 100000000);
                                        var postData = {"id": id, "method": "songloft_config.sh", "params": [4], "fields": {}};
                                        $.ajax({
                                                type: "POST", url: "/_api/",
                                                data: JSON.stringify(postData), dataType: "json",
                                                complete: function(){
                                                        logTrimming = false;
                                                        setTimeout(function(){ get_log(action ? 1 : 0); }, 200);
                                                }
                                        });
                                        return;
                                }
                        }
                        if (action) { logTimer = setTimeout(function(){ get_log(1); }, 1200); }
                },
                error: function(){
                        if (action) { logTimer = setTimeout(function(){ get_log(1); }, 1500); }
                }
        });
}

function check_status() {
        if (statusTimer) { clearTimeout(statusTimer); statusTimer = null; }
        if (dbus["songloft_enable"] != "1") {
                E("songloft_status").innerHTML = "未启用";
                E("btn_web").style.display = "none";
                return;
        }
        var id = parseInt(Math.random() * 100000000);
        var postData = {"id": id, "method": "songloft_status.sh", "params": [1], "fields": ""};
        $.ajax({
                type: "POST", url: "/_api/", async: true,
                data: JSON.stringify(postData), dataType: "json",
                success: function(response) {
                        var result = response.result || "";
                        try { E("songloft_status").innerHTML = result; } catch(e) {}
                        E("btn_web").style.display = (result.indexOf("运行中") !== -1) ? "inline-block" : "none";
                        statusTimer = setTimeout(check_status, 5000);
                },
                error: function(){
                        E("songloft_status").innerHTML = "获取运行状态失败";
                        E("btn_web").style.display = "none";
                        statusTimer = setTimeout(check_status, 8000);
                }
        });
}

function openWebInterface() {
        var port = $.trim(E("songloft_listen_port").value || "58091");
        var basePath = $.trim(E("songloft_base_path").value || "");
        if (basePath && basePath.charAt(0) !== "/") { basePath = "/" + basePath; }
        var url = "http://" + window.location.hostname + ":" + port + basePath;
        window.open(url, "_blank");
}
</script>
</head>
<body onload="init();">
        <div id="TopBanner"></div>
        <div id="Loading" class="popup_bg"></div>
        <iframe name="hidden_frame" id="hidden_frame" src="" width="0" height="0" frameborder="0"></iframe>
        <table class="content" align="center" cellpadding="0" cellspacing="0">
                <tr>
                        <td width="17">&nbsp;</td>
                        <td valign="top" width="202">
                                <div id="mainMenu"></div>
                                <div id="subMenu"></div>
                        </td>
                        <td valign="top">
                                <div id="tabMenu" class="submenuBlock"></div>
                                <table width="98%" border="0" align="left" cellpadding="0" cellspacing="0">
                                        <tr>
                                                <td align="left" valign="top">
                                                        <table width="760px" border="0" cellpadding="5" cellspacing="0" bordercolor="#6b8fa3" class="FormTitle" id="FormTitle">
                                                                <tr>
                                                                        <td bgcolor="#4D595D" colspan="3" valign="top">
                                                                                <div>&nbsp;</div>
                                                                                <div class="formfonttitle">媒体服务 - SongLoft <label id="songloft_version"></label></div>
                                                                                <div style="float:right; width:15px; height:25px;margin-top:-20px">
                                                                                        <img id="return_btn" onclick="reload_Soft_Center();" align="right"
                                                                                                style="cursor:pointer;position:absolute;margin-left:-30px;margin-top:-25px;"
                                                                                                title="返回软件中心"
                                                                                                src="/images/backprev.png"
                                                                                                onMouseOver="this.src='/images/backprevclick.png'"
                                                                                                onMouseOut="this.src='/images/backprev.png'">
                                                                                        </img>
                                                                                </div>
                                                                                <div style="margin:10px 0 10px 5px;" class="splitLine"></div>

                                                                                <div class="SimpleNote">
                                                                                        <div>1. SongLoft 是一个轻量级音乐库管理与串流服务，支持通过环境变量或下方表单配置启动参数。</div>
                                                                                        <div>2. 环境变量优先级高于表单配置：<span style="color:#00c6ff;font-weight:600;">ADMIN_USERNAME / ADMIN_PASSWORD / LISTEN_PORT / DB_PATH / BASE_PATH</span>。</div>
                                                                                        <div>3. 若需自定义二进制路径（如外置存储），可在"二进制路径"中填写绝对路径；留空则使用默认路径 <span style="color:#00c6ff;">/koolshare/bin/songloft</span>。</div>
                                                                                </div>

                                                                                <div style="margin:10px 0 10px 5px;" class="splitLine"></div>

                                                                                <table width="100%" border="1" align="center" cellpadding="4" cellspacing="0" class="FormTable">
                                                                                        <tr>
                                                                                                <th width="200">启用 SongLoft</th>
                                                                                                <td>
                                                                                                        <div class="switch_field" style="display:table-cell">
                                                                                                                <label for="songloft_enable">
                                                                                                                        <input id="songloft_enable" class="switch" type="checkbox" style="display:none;">
                                                                                                                        <div class="switch_container">
                                                                                                                                <div class="switch_bar"></div>
                                                                                                                                <div class="switch_circle transition_style">
                                                                                                                                        <div></div>
                                                                                                                                </div>
                                                                                                                        </div>
                                                                                                                </label>
                                                                                                        </div>
                                                                                                </td>
                                                                                        </tr>
                                                                                        <tr id="tr_status">
                                                                                                <th>运行状态</th>
                                                                                                <td>
                                                                                                        <span id="songloft_status">加载中...</span>
                                                                                                        <a id="btn_web" class="songloft_btn" href="javascript:void(0);" onclick="openWebInterface()">打开 WEB 界面</a>
                                                                                                </td>
                                                                                        </tr>
                                                                                        <tr id="tr_port">
                                                                                                <th>监听端口<br/><span class="hint-color" style="font-weight:normal;font-size:11px;">环境变量：LISTEN_PORT</span></th>
                                                                                                <td>
                                                                                                        <input id="songloft_listen_port" class="input_ss_table" style="width:160px;" value=""
                                                                                                                placeholder="默认：58091"
                                                                                                                autocomplete="off" autocorrect="off" autocapitalize="off" spellcheck="false" />
                                                                                                        <span style="margin-left:10px;" class="hint-color">对应 -port 参数</span>
                                                                                                </td>
                                                                                        </tr>
                                                                                        <tr id="tr_db_path">
                                                                                                <th>根目录</th>
                                                                                                <td>
                                                                                                        <input id="songloft_db_path" class="input_ss_table" style="width:360px;" value=""
                                                                                                                placeholder="例如：/koolshare/songloft"
                                                                                                                autocomplete="off" autocorrect="off" autocapitalize="off" spellcheck="false" />
                                                                                                        <span style="margin-left:10px;" class="hint-color">工作目录</span>
                                                                                                </td>
                                                                                        </tr>
                                                                                        <tr id="tr_username">
                                                                                                <th>管理员用户名<br/><span class="hint-color" style="font-weight:normal;font-size:11px;">环境变量：ADMIN_USERNAME</span></th>
                                                                                                <td>
                                                                                                        <input id="songloft_admin_username" class="input_ss_table" style="width:240px;" value=""
                                                                                                                placeholder="留空则不设置"
                                                                                                                autocomplete="off" autocorrect="off" autocapitalize="off" spellcheck="false" />
                                                                                                        <span style="margin-left:10px;" class="hint-color">对应 -username 参数</span>
                                                                                                </td>
                                                                                        </tr>
                                                                                        <tr id="tr_password">
                                                                                                <th>管理员密码<br/><span class="hint-color" style="font-weight:normal;font-size:11px;">环境变量：ADMIN_PASSWORD</span></th>
                                                                                                <td>
                                                                                                        <input id="songloft_admin_password" class="input_ss_table" style="width:240px;" type="password" value=""
                                                                                                                placeholder="留空则不设置"
                                                                                                                autocomplete="new-password" spellcheck="false" />
                                                                                                        <span style="margin-left:10px;" class="hint-color">对应 -password 参数</span>
                                                                                                </td>
                                                                                        </tr>
                                                                                        <tr id="tr_base_path">
                                                                                                <th>URL 基础路径<br/><span class="hint-color" style="font-weight:normal;font-size:11px;">环境变量：BASE_PATH</span></th>
                                                                                                <td>
                                                                                                        <input id="songloft_base_path" class="input_ss_table" style="width:240px;" value=""
                                                                                                                placeholder="例如：/songloft（反向代理时使用）"
                                                                                                                autocomplete="off" autocorrect="off" autocapitalize="off" spellcheck="false" />
                                                                                                        <span style="margin-left:10px;" class="hint-color">对应 -base-path 参数</span>
                                                                                                </td>
                                                                                        </tr>
                                                                                        <tr id="tr_bin_path">
                                                                                                <th>二进制路径<br/><span class="hint-color" style="font-weight:normal;font-size:11px;">留空使用默认</span></th>
                                                                                                <td>
                                                                                                        <input id="songloft_bin_path" class="input_ss_table" style="width:400px;" value=""
                                                                                                                placeholder="留空使用 /koolshare/bin/songloft"
                                                                                                                autocomplete="off" autocorrect="off" autocapitalize="off" spellcheck="false" />
                                                                                                </td>
                                                                                        </tr>
                                                                                </table>

                                                                                <div class="apply_gen">
                                                                                        <input class="button_gen" id="btn_apply" type="button" value="提交" onclick="apply_config()" />
                                                                                        <input class="button_gen" id="btn_log" style="margin-left:10px;" type="button" value="查看日志" onclick="open_log_popup()" />
                                                                                </div>

                                                                        </td>
                                                                </tr>
                                                        </table>
                                                </td>
                                        </tr>
                                </table>
                        </td>
                        <td width="10" align="center" valign="top"></td>
                </tr>
        </table>
        <div id="songloft_log_mask" class="songloft_mask"></div>
        <div id="songloft_log_popup" class="songloft_popup">
                <div class="songloft_popup_head">运行日志</div>
                <div class="songloft_popup_body">
                        <div class="soft_setting_log">
                                <textarea cols="63" rows="18" wrap="on" readonly="readonly" id="log_text"
                                        class="soft_setting_log1"
                                        autocomplete="off" autocorrect="off" autocapitalize="off" spellcheck="false"></textarea>
                        </div>
                        <div class="apply_gen" style="background:#000;">
                                <input class="button_gen" id="btn_clear" type="button" value="清空日志" onclick="clear_log()" />
                                <input class="button_gen" style="margin-left:10px;" type="button" value="关闭" onclick="close_log_popup()" />
                        </div>
                </div>
        </div>
        <div id="footer"></div>
</body>
</html>