# Windows-PowerShell-Wireguard-
一个Windows PowerShell脚本，用于自动生成Wireguard服务器端和客户端配置文件  
最近在发现Wireguard这个应用在作为VPN方面很好用，遂试试。但是在建立服务器和客户端配置文件时要生成密钥而且还要放在正确位置并合理设置  非常繁琐，所以让ai写了一个脚本用于实现自动生成配置文件。  
另外由于基本上没有公网IPV4地址，要远程访问家里电脑的共享文件挺麻烦，但是好在现在几乎每个设备都有自己的公网IPV6，所以这个脚本可以自动获取本机IPV6并生成脚本。  
使用方法：  
1、下载脚本文件  
2、管理员打开Windows Powershell  
3、打开脚本文件，复制脚本代码到Poweshell （不建议直接执行脚本文件）  
4、回车 等待脚本自动执行，执行完毕后脚本最下方会显示配置文件信息。  
5、脚本执行完毕后会将配置文件自动存在D盘下wireguard files 文件夹下（没有会自动新建）  
6、分别在电脑端和手机端导入配置文件  
7、完成！  
注：本人非计科专业，如有问题还请见谅~  
<img width="1347" height="1096" alt="无标题" src="https://github.com/user-attachments/assets/452662ae-ba29-4826-96d5-516924571e29" />
