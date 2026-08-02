package com.mindskip.xzs.controller.admin;

import com.github.pagehelper.PageInfo;
import com.mindskip.xzs.base.BaseApiController;
import com.mindskip.xzs.base.RestResponse;
import com.mindskip.xzs.domain.QuestionGroup;
import com.mindskip.xzs.service.QuestionGroupService;
import com.mindskip.xzs.viewmodel.admin.questiongroup.QuestionGroupEditRequestVM;
import com.mindskip.xzs.viewmodel.admin.questiongroup.QuestionGroupPageRequestVM;
import com.mindskip.xzs.viewmodel.admin.questiongroup.QuestionGroupResponseVM;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;

import javax.validation.Valid;

@RestController("AdminQuestionGroupController")
@RequestMapping("/api/admin/question/group")
public class QuestionGroupController extends BaseApiController {
    private final QuestionGroupService questionGroupService;

    @Autowired
    public QuestionGroupController(QuestionGroupService questionGroupService) {
        this.questionGroupService = questionGroupService;
    }

    @PostMapping("/page")
    public RestResponse<PageInfo<QuestionGroupResponseVM>> page(@RequestBody QuestionGroupPageRequestVM model) {
        return RestResponse.ok(questionGroupService.page(model));
    }

    @PostMapping("/select/{id}")
    public RestResponse<QuestionGroupResponseVM> select(@PathVariable Integer id) {
        QuestionGroupResponseVM vm = questionGroupService.selectFullById(id);
        return vm == null ? RestResponse.fail(2, "题组不存在") : RestResponse.ok(vm);
    }

    @PostMapping("/edit")
    public RestResponse<QuestionGroupResponseVM> edit(@RequestBody @Valid QuestionGroupEditRequestVM model) {
        try {
            QuestionGroup group = questionGroupService.save(model, getCurrentUser().getId());
            return RestResponse.ok(questionGroupService.selectFullById(group.getId()));
        } catch (IllegalArgumentException e) {
            return RestResponse.fail(2, e.getMessage());
        }
    }

    @PostMapping("/delete/{id}")
    public RestResponse delete(@PathVariable Integer id) {
        questionGroupService.softDelete(id);
        return RestResponse.ok();
    }
}
