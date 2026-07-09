package com.mindskip.xzs.controller.admin;


import com.mindskip.xzs.base.BaseApiController;
import com.mindskip.xzs.base.RestResponse;
import com.mindskip.xzs.domain.TaskExam;
import com.mindskip.xzs.domain.User;
import com.mindskip.xzs.service.ClassScopeService;
import com.mindskip.xzs.service.TaskExamService;
import com.mindskip.xzs.utility.DateTimeUtil;
import com.mindskip.xzs.utility.PageInfoHelper;
import com.mindskip.xzs.viewmodel.admin.task.TaskPageRequestVM;
import com.mindskip.xzs.viewmodel.admin.task.TaskPageResponseVM;
import com.mindskip.xzs.viewmodel.admin.task.TaskRequestVM;
import com.github.pagehelper.PageInfo;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;

import javax.validation.Valid;

@RestController("AdminTaskController")
@RequestMapping(value = "/api/admin/task")
public class TaskController extends BaseApiController {

    private final TaskExamService taskExamService;
    private final ClassScopeService classScopeService;

    @Autowired
    public TaskController(TaskExamService taskExamService, ClassScopeService classScopeService) {
        this.taskExamService = taskExamService;
        this.classScopeService = classScopeService;
    }

    @RequestMapping(value = "/page", method = RequestMethod.POST)
    public RestResponse<PageInfo<TaskPageResponseVM>> pageList(@RequestBody TaskPageRequestVM model) {
        User currentUser = getCurrentUser();
        if (classScopeService.isTeacher(currentUser)) {
            model.setClassIds(classScopeService.teacherClassIds(currentUser));
        }
        PageInfo<TaskExam> pageInfo = taskExamService.page(model);
        PageInfo<TaskPageResponseVM> page = PageInfoHelper.copyMap(pageInfo, m -> {
            TaskPageResponseVM vm = modelMapper.map(m, TaskPageResponseVM.class);
            vm.setCreateTime(DateTimeUtil.dateFormat(m.getCreateTime()));
            return vm;
        });
        return RestResponse.ok(page);
    }


    @RequestMapping(value = "/edit", method = RequestMethod.POST)
    public RestResponse edit(@RequestBody @Valid TaskRequestVM model) {
        taskExamService.edit(model, getCurrentUser());
        TaskRequestVM vm = taskExamService.taskExamToVM(model.getId());
        return RestResponse.ok(vm);
    }


    @RequestMapping(value = "/select/{id}", method = RequestMethod.POST)
    public RestResponse<TaskRequestVM> select(@PathVariable Integer id) {
        requireTaskAccess(id);
        TaskRequestVM vm = taskExamService.taskExamToVM(id);
        return RestResponse.ok(vm);
    }

    @RequestMapping(value = "/delete/{id}", method = RequestMethod.POST)
    public RestResponse delete(@PathVariable Integer id) {
        requireTaskAccess(id);
        TaskExam taskExam = taskExamService.selectById(id);
        taskExam.setDeleted(true);
        taskExamService.updateByIdFilter(taskExam);
        return RestResponse.ok();
    }

    private void requireTaskAccess(Integer id) {
        User currentUser = getCurrentUser();
        if (classScopeService.isTeacher(currentUser)) {
            TaskExam taskExam = taskExamService.selectById(id);
            classScopeService.requireClassAccess(currentUser, taskExam == null ? null : taskExam.getClassId());
        }
    }
}
