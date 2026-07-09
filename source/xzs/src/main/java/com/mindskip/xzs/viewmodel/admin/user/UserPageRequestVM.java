package com.mindskip.xzs.viewmodel.admin.user;

import com.mindskip.xzs.base.BasePage;

import java.util.List;


public class UserPageRequestVM extends BasePage {

    private String userName;
    private Integer role;
    private Integer classId;
    private List<Integer> classIds;

    public String getUserName() {
        return userName;
    }

    public void setUserName(String userName) {
        this.userName = userName;
    }

    public Integer getRole() {
        return role;
    }

    public void setRole(Integer role) {
        this.role = role;
    }

    public Integer getClassId() {
        return classId;
    }

    public void setClassId(Integer classId) {
        this.classId = classId;
    }

    public List<Integer> getClassIds() {
        return classIds;
    }

    public void setClassIds(List<Integer> classIds) {
        this.classIds = classIds;
    }
}
