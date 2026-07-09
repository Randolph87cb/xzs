package com.mindskip.xzs.controller.admin;

import com.github.pagehelper.PageInfo;
import com.mindskip.xzs.base.BaseApiController;
import com.mindskip.xzs.base.RestResponse;
import com.mindskip.xzs.domain.SchoolClass;
import com.mindskip.xzs.domain.User;
import com.mindskip.xzs.domain.enums.RoleEnum;
import com.mindskip.xzs.service.ClassScopeService;
import com.mindskip.xzs.service.SchoolClassService;
import com.mindskip.xzs.service.UserService;
import com.mindskip.xzs.utility.PageInfoHelper;
import com.mindskip.xzs.viewmodel.admin.clazz.ClassEditRequestVM;
import com.mindskip.xzs.viewmodel.admin.clazz.ClassPageRequestVM;
import com.mindskip.xzs.viewmodel.admin.clazz.ClassResponseVM;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;

import javax.validation.Valid;
import java.util.Date;
import java.util.List;
import java.util.stream.Collectors;

@RestController("AdminClassController")
@RequestMapping(value = "/api/admin/class")
public class ClassController extends BaseApiController {

    private final SchoolClassService schoolClassService;
    private final ClassScopeService classScopeService;
    private final UserService userService;

    @Autowired
    public ClassController(SchoolClassService schoolClassService, ClassScopeService classScopeService, UserService userService) {
        this.schoolClassService = schoolClassService;
        this.classScopeService = classScopeService;
        this.userService = userService;
    }

    @RequestMapping(value = "/page", method = RequestMethod.POST)
    public RestResponse<PageInfo<ClassResponseVM>> page(@RequestBody ClassPageRequestVM model) {
        User currentUser = getCurrentUser();
        applyClassScope(model, currentUser);
        PageInfo<SchoolClass> pageInfo = schoolClassService.page(model);
        PageInfo<ClassResponseVM> page = PageInfoHelper.copyMap(pageInfo, ClassResponseVM::from);
        return RestResponse.ok(page);
    }

    @RequestMapping(value = "/options", method = RequestMethod.POST)
    public RestResponse<List<ClassResponseVM>> options(@RequestBody(required = false) ClassPageRequestVM model) {
        ClassPageRequestVM request = model == null ? new ClassPageRequestVM() : model;
        applyClassScope(request, getCurrentUser());
        List<ClassResponseVM> options = schoolClassService.selectOptions(request).stream()
                .map(ClassResponseVM::from)
                .collect(Collectors.toList());
        return RestResponse.ok(options);
    }

    @RequestMapping(value = "/select/{id}", method = RequestMethod.POST)
    public RestResponse<ClassResponseVM> select(@PathVariable Integer id) {
        classScopeService.requireClassAccess(getCurrentUser(), id);
        SchoolClass schoolClass = schoolClassService.selectById(id);
        if (schoolClass == null || Boolean.TRUE.equals(schoolClass.getDeleted())) {
            return RestResponse.fail(2, "班级不存在");
        }
        return RestResponse.ok(ClassResponseVM.from(schoolClass));
    }

    @RequestMapping(value = "/edit", method = RequestMethod.POST)
    public RestResponse<SchoolClass> edit(@RequestBody @Valid ClassEditRequestVM model) {
        User currentUser = getCurrentUser();
        if (model.getId() != null) {
            classScopeService.requireClassAccess(currentUser, model.getId());
        }
        Integer teacherId = classScopeService.isTeacher(currentUser) ? currentUser.getId() : model.getTeacherId();
        if (teacherId == null) {
            return RestResponse.fail(2, "负责老师不能为空");
        }
        User teacher = userService.getUserById(teacherId);
        if (teacher == null || RoleEnum.TEACHER.getCode() != teacher.getRole()) {
            return RestResponse.fail(2, "负责老师不存在");
        }

        Date now = new Date();
        SchoolClass schoolClass = modelMapper.map(model, SchoolClass.class);
        schoolClass.setTeacherId(teacherId);
        if (schoolClass.getStatus() == null) {
            schoolClass.setStatus(1);
        }
        if (model.getId() == null) {
            schoolClass.setCreateTime(now);
            schoolClass.setDeleted(false);
            schoolClassService.insertByFilter(schoolClass);
        } else {
            schoolClass.setModifyTime(now);
            schoolClassService.updateByIdFilter(schoolClass);
        }
        return RestResponse.ok(schoolClass);
    }

    @RequestMapping(value = "/delete/{id}", method = RequestMethod.POST)
    public RestResponse delete(@PathVariable Integer id) {
        classScopeService.requireClassAccess(getCurrentUser(), id);
        SchoolClass schoolClass = schoolClassService.selectById(id);
        if (schoolClass == null || Boolean.TRUE.equals(schoolClass.getDeleted())) {
            return RestResponse.fail(2, "班级不存在");
        }
        schoolClass.setDeleted(true);
        schoolClass.setModifyTime(new Date());
        schoolClassService.updateByIdFilter(schoolClass);
        return RestResponse.ok();
    }

    private void applyClassScope(ClassPageRequestVM model, User currentUser) {
        if (classScopeService.isTeacher(currentUser)) {
            model.setClassIds(classScopeService.teacherClassIds(currentUser));
            model.setTeacherId(null);
        }
    }
}
