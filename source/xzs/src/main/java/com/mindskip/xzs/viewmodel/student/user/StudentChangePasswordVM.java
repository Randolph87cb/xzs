package com.mindskip.xzs.viewmodel.student.user;

import javax.validation.constraints.NotBlank;
import javax.validation.constraints.Size;

public class StudentChangePasswordVM {

    @NotBlank
    private String oldPassword;

    @NotBlank
    @Size(min = 6, max = 64)
    private String newPassword;

    @NotBlank
    private String confirmPassword;

    public String getOldPassword() {
        return oldPassword;
    }

    public void setOldPassword(String oldPassword) {
        this.oldPassword = oldPassword;
    }

    public String getNewPassword() {
        return newPassword;
    }

    public void setNewPassword(String newPassword) {
        this.newPassword = newPassword;
    }

    public String getConfirmPassword() {
        return confirmPassword;
    }

    public void setConfirmPassword(String confirmPassword) {
        this.confirmPassword = confirmPassword;
    }
}
