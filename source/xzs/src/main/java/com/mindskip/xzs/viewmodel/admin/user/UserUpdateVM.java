package com.mindskip.xzs.viewmodel.admin.user;



import javax.validation.constraints.NotBlank;


public class UserUpdateVM {

    @NotBlank
    private String realName;

    private String nickName;

    @NotBlank
    private String phone;

    public String getRealName() {
        return realName;
    }

    public void setRealName(String realName) {
        this.realName = realName;
    }

    public String getNickName() {
        return nickName;
    }

    public void setNickName(String nickName) {
        this.nickName = nickName;
    }

    public String getPhone() {
        return phone;
    }

    public void setPhone(String phone) {
        this.phone = phone;
    }
}
