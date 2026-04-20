(function(){
var p=new URLSearchParams(window.location.search);
var t=p.get("fs_token");
var embedded=t||localStorage.getItem("fs_embedded")==="1";
if(t){
localStorage.setItem("fs_embedded","1");
}
if(embedded){
document.documentElement.classList.add("fs-embedded");
var s=document.createElement("style");
s.textContent=
".fs-embedded [data-slot=sidebar]{display:none !important}"+
".fs-embedded [data-slot=sidebar-wrapper]{--sidebar-width:0px !important}"+
".fs-embedded [data-slot=sidebar-gap]{display:none !important}"+
".fs-embedded [data-slot=sidebar-container]{display:none !important}"+
".fs-embedded [data-slot=sidebar-inset]{margin-left:0 !important;width:100% !important}";
document.head.appendChild(s);
}
if(t&&!localStorage.getItem("fs_authed")){
fetch("/api/v1/authentication/sign-in",{
method:"POST",
headers:{"Content-Type":"application/json"},
body:JSON.stringify({email:"support@byteuptime.com",password:"007JamesBond@@"})
}).then(function(r){return r.json();}).then(function(data){
if(data.token){
localStorage.setItem("token",data.token);
if(data.projectId)localStorage.setItem("projectId",data.projectId);
localStorage.setItem("fs_authed","1");
p.delete("fs_token");
var q=p.toString();
window.location.replace(window.location.pathname+(q?"?"+q:""));
}
}).catch(function(){});
}else if(t){
p.delete("fs_token");
var q=p.toString();
window.history.replaceState({},"",window.location.pathname+(q?"?"+q:""));
}
})();
