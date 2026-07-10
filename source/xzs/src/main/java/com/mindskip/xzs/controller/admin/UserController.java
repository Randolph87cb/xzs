package com.mindskip.xzs.controller.admin;

import com.mindskip.xzs.base.BaseApiController;
import com.mindskip.xzs.base.RestResponse;
import com.mindskip.xzs.domain.other.KeyValue;
import com.mindskip.xzs.domain.Subject;
import com.mindskip.xzs.domain.User;
import com.mindskip.xzs.domain.UserEventLog;
import com.mindskip.xzs.domain.enums.RoleEnum;
import com.mindskip.xzs.domain.enums.UserStatusEnum;
import com.mindskip.xzs.service.AuthenticationService;
import com.mindskip.xzs.service.ClassScopeService;
import com.mindskip.xzs.service.SubjectService;
import com.mindskip.xzs.service.UserEventLogService;
import com.mindskip.xzs.service.UserService;
import com.mindskip.xzs.utility.DateTimeUtil;
import com.mindskip.xzs.viewmodel.admin.user.*;
import com.mindskip.xzs.utility.PageInfoHelper;
import com.github.pagehelper.PageInfo;

import org.apache.commons.lang3.StringUtils;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;

import javax.validation.Valid;
import java.util.Date;
import java.util.List;
import java.util.UUID;


@RestController("AdminUserController")
@RequestMapping(value = "/api/admin/user")
public class UserController extends BaseApiController {

    private final UserService userService;
    private final UserEventLogService userEventLogService;
    private final AuthenticationService authenticationService;
    private final ClassScopeService classScopeService;
    private final SubjectService subjectService;

    @Autowired
    public UserController(UserService userService, UserEventLogService userEventLogService, AuthenticationService authenticationService, ClassScopeService classScopeService, SubjectService subjectService) {
        this.userService = userService;
        this.userEventLogService = userEventLogService;
        this.authenticationService = authenticationService;
        this.classScopeService = classScopeService;
        this.subjectService = subjectService;
    }


    @RequestMapping(value = "/page/list", method = RequestMethod.POST)
    public RestResponse<PageInfo<UserResponseVM>> pageList(@RequestBody UserPageRequestVM model) {
        User currentUser = getCurrentUser();
        if (classScopeService.isTeacher(currentUser)) {
            model.setRole(RoleEnum.STUDENT.getCode());
            model.setClassIds(classScopeService.teacherClassIds(currentUser));
        }
        PageInfo<User> pageInfo = userService.userPage(model);
        PageInfo<UserResponseVM> page = PageInfoHelper.copyMap(pageInfo, d -> UserResponseVM.from(d));
        return RestResponse.ok(page);
    }


    @RequestMapping(value = "/event/page/list", method = RequestMethod.POST)
    public RestResponse<PageInfo<UserEventLogVM>> eventPageList(@RequestBody UserEventPageRequestVM model) {
        PageInfo<UserEventLog> pageInfo = userEventLogService.page(model);
        PageInfo<UserEventLogVM> page = PageInfoHelper.copyMap(pageInfo, d -> {
            UserEventLogVM vm = modelMapper.map(d, UserEventLogVM.class);
            vm.setCreateTime(DateTimeUtil.dateFormat(d.getCreateTime()));
            return vm;
        });
        return RestResponse.ok(page);
    }

    @RequestMapping(value = "/select/{id}", method = RequestMethod.POST)
    public RestResponse<UserResponseVM> select(@PathVariable Integer id) {
        User user = userService.getUserById(id);
        if (classScopeService.isTeacher(getCurrentUser())) {
            classScopeService.requireStudentAccess(getCurrentUser(), id);
        }
        UserResponseVM userVm = UserResponseVM.from(user);
        return RestResponse.ok(userVm);
    }

    @RequestMapping(value = "/current", method = RequestMethod.POST)
    public RestResponse<UserResponseVM> current() {
        User user = getCurrentUser();
        UserResponseVM userVm = UserResponseVM.from(user);
        return RestResponse.ok(userVm);
    }


    @RequestMapping(value = "/edit", method = RequestMethod.POST)
    public RestResponse<User> edit(@RequestBody @Valid UserCreateVM model) {
        User currentUser = getCurrentUser();
        User before = model.getId() == null ? null : userService.getUserById(model.getId());
        RestResponse<User> scopeError = validateUserScope(currentUser, model, before);
        if (scopeError != null) {
            return scopeError;
        }
        if (model.getId() == null) {  //create
            User existUser = userService.getUserByUserName(model.getUserName());
            if (null != existUser) {
                return new RestResponse<>(2, "用户已存在");
            }

            if (StringUtils.isBlank(model.getPassword())) {
                return new RestResponse<>(3, "密码不能为空");
            }
        }
        if (StringUtils.isBlank(model.getBirthDay())) {
            model.setBirthDay(null);
        }
        if (classScopeService.isTeacher(currentUser)) {
            model.setRole(RoleEnum.STUDENT.getCode());
        }
        RestResponse<User> targetSubjectError = validateAndNormalizeTargetSubject(model, before);
        if (targetSubjectError != null) {
            return targetSubjectError;
        }
        User user = modelMapper.map(model, User.class);
        if (user.getRole() == null || RoleEnum.STUDENT.getCode() != user.getRole()) {
            user.setClassId(null);
        }

        if (model.getId() == null) {
            String encodePwd = authenticationService.pwdEncode(model.getPassword());
            user.setPassword(encodePwd);
            user.setUserUuid(UUID.randomUUID().toString());
            user.setCreateTime(new Date());
            user.setLastActiveTime(new Date());
            user.setDeleted(false);
            userService.insertByFilter(user);
        } else {
            if (!StringUtils.isBlank(model.getPassword())) {
                String encodePwd = authenticationService.pwdEncode(model.getPassword());
                user.setPassword(encodePwd);
            } else {
                user.setPassword(null);
            }
            user.setModifyTime(new Date());
            userService.updateByIdFilter(user);
            userService.updateTargetSubjectId(user.getId(), user.getTargetSubjectId());
        }
        return RestResponse.ok(user);
    }


    @RequestMapping(value = "/update", method = RequestMethod.POST)
    public RestResponse update(@RequestBody @Valid UserUpdateVM model) {
        User user = userService.selectById(getCurrentUser().getId());
        modelMapper.map(model, user);
        user.setModifyTime(new Date());
        userService.updateByIdFilter(user);
        return RestResponse.ok();
    }


    @RequestMapping(value = "/changeStatus/{id}", method = RequestMethod.POST)
    public RestResponse<Integer> changeStatus(@PathVariable Integer id) {
        if (classScopeService.isTeacher(getCurrentUser())) {
            classScopeService.requireStudentAccess(getCurrentUser(), id);
        }
        User user = userService.getUserById(id);
        UserStatusEnum userStatusEnum = UserStatusEnum.fromCode(user.getStatus());
        Integer newStatus = userStatusEnum == UserStatusEnum.Enable ? UserStatusEnum.Disable.getCode() : UserStatusEnum.Enable.getCode();
        user.setStatus(newStatus);
        user.setModifyTime(new Date());
        userService.updateByIdFilter(user);
        return RestResponse.ok(newStatus);
    }


    @RequestMapping(value = "/delete/{id}", method = RequestMethod.POST)
    public RestResponse delete(@PathVariable Integer id) {
        if (classScopeService.isTeacher(getCurrentUser())) {
            classScopeService.requireStudentAccess(getCurrentUser(), id);
        }
        User user = userService.getUserById(id);
        user.setDeleted(true);
        userService.updateByIdFilter(user);
        return RestResponse.ok();
    }


    @RequestMapping(value = "/selectByUserName", method = RequestMethod.POST)
    public RestResponse<List<KeyValue>> selectByUserName(@RequestBody String userName) {
        User currentUser = getCurrentUser();
        List<KeyValue> keyValues = classScopeService.isTeacher(currentUser) ?
                userService.selectStudentByUserNameInClasses(userName, classScopeService.teacherClassIds(currentUser)) :
                userService.selectByUserName(userName);
        return RestResponse.ok(keyValues);
    }

    private RestResponse<User> validateUserScope(User currentUser, UserCreateVM model, User before) {
        if (classScopeService.isTeacher(currentUser)) {
            if (model.getRole() != null && RoleEnum.STUDENT.getCode() != model.getRole()) {
                return RestResponse.fail(2, "老师只能管理学生账号");
            }
            if (before != null) {
                classScopeService.requireStudentAccess(currentUser, before.getId());
            }
            Integer classId = model.getClassId();
            if (classId == null && before != null) {
                classId = before.getClassId();
                model.setClassId(classId);
            }
            if (classId == null) {
                return RestResponse.fail(2, "学生班级不能为空");
            }
            if (!classScopeService.canManageClass(currentUser, classId)) {
                return RestResponse.fail(2, "没有该班级的管理权限");
            }
            return null;
        }
        if (before != null && RoleEnum.STUDENT.getCode() == before.getRole() && model.getClassId() != null && !classScopeService.canManageClass(currentUser, model.getClassId())) {
            return RestResponse.fail(2, "班级不存在");
        }
        if (model.getRole() != null && RoleEnum.STUDENT.getCode() == model.getRole() && model.getClassId() == null && before == null) {
            return RestResponse.fail(2, "学生班级不能为空");
        }
        return null;
    }

    private RestResponse<User> validateAndNormalizeTargetSubject(UserCreateVM model, User before) {
        Integer role = model.getRole();
        if (role == null && before != null) {
            role = before.getRole();
            model.setRole(role);
        }

        if (role == null || RoleEnum.STUDENT.getCode() != role) {
            model.setTargetSubjectId(null);
            return null;
        }

        Integer targetSubjectId = model.getTargetSubjectId();
        if (targetSubjectId == null) {
            return null;
        }

        Subject subject = subjectService.selectById(targetSubjectId);
        if (subject == null || Boolean.TRUE.equals(subject.getDeleted())) {
            return RestResponse.fail(2, "目标科目不存在");
        }
        return null;
    }

}
