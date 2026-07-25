package com.mindskip.xzs.controller.student;

import com.mindskip.xzs.base.BaseApiController;
import com.mindskip.xzs.base.RestResponse;
import com.mindskip.xzs.domain.ExamPaper;
import com.mindskip.xzs.domain.Subject;
import com.mindskip.xzs.service.ExamPaperAnswerService;
import com.mindskip.xzs.service.ExamPaperService;
import com.mindskip.xzs.service.SubjectService;
import com.mindskip.xzs.utility.DateTimeUtil;
import com.mindskip.xzs.utility.PageInfoHelper;
import com.mindskip.xzs.viewmodel.admin.exam.ExamPaperEditRequestVM;
import com.mindskip.xzs.viewmodel.student.education.SubjectVM;
import com.mindskip.xzs.viewmodel.student.exam.ExamPaperBootstrapRequestVM;
import com.mindskip.xzs.viewmodel.student.exam.ExamPaperBootstrapResponseVM;
import com.mindskip.xzs.viewmodel.student.exam.ExamPaperPageResponseVM;
import com.mindskip.xzs.viewmodel.student.exam.ExamPaperPageVM;
import com.mindskip.xzs.viewmodel.student.exam.SmartTrainingCreateRequestVM;
import com.mindskip.xzs.viewmodel.student.exam.SmartTrainingCreateResponseVM;
import com.github.pagehelper.PageInfo;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.web.bind.annotation.*;

import javax.validation.Valid;
import java.util.Collections;
import java.util.List;
import java.util.stream.Collectors;

@RestController("StudentExamPaperController")
@RequestMapping(value = "/api/student/exam/paper")
public class ExamPaperController extends BaseApiController {

    private final ExamPaperService examPaperService;
    private final ExamPaperAnswerService examPaperAnswerService;
    private final SubjectService subjectService;
    private final ApplicationEventPublisher eventPublisher;

    @Autowired
    public ExamPaperController(ExamPaperService examPaperService, ExamPaperAnswerService examPaperAnswerService, SubjectService subjectService, ApplicationEventPublisher eventPublisher) {
        this.examPaperService = examPaperService;
        this.examPaperAnswerService = examPaperAnswerService;
        this.subjectService = subjectService;
        this.eventPublisher = eventPublisher;
    }


    @RequestMapping(value = "/select/{id}", method = RequestMethod.POST)
    public RestResponse<ExamPaperEditRequestVM> select(@PathVariable Integer id) {
        ExamPaperEditRequestVM vm = examPaperService.examPaperToVM(id);
        return RestResponse.ok(vm);
    }

    @RequestMapping(value = "/smartTraining/create", method = RequestMethod.POST)
    public RestResponse<SmartTrainingCreateResponseVM> createSmartTraining(@RequestBody @Valid SmartTrainingCreateRequestVM model) {
        try {
            ExamPaper examPaper = examPaperService.createSmartTrainingPaper(model.getSubjectId(), getCurrentUser());
            return RestResponse.ok(new SmartTrainingCreateResponseVM(examPaper.getId()));
        } catch (IllegalArgumentException e) {
            return RestResponse.fail(2, e.getMessage());
        }
    }


    @RequestMapping(value = "/pageList", method = RequestMethod.POST)
    public RestResponse<PageInfo<ExamPaperPageResponseVM>> pageList(@RequestBody @Valid ExamPaperPageVM model) {
        PageInfo<ExamPaper> pageInfo = examPaperService.studentPage(model);
        return RestResponse.ok(toPageResponse(pageInfo));
    }

    @RequestMapping(value = "/bootstrap", method = RequestMethod.POST)
    public RestResponse<ExamPaperBootstrapResponseVM> bootstrap(@RequestBody @Valid ExamPaperBootstrapRequestVM model) {
        List<Subject> subjects = subjectService.allSubject();
        List<SubjectVM> subjectVMS = subjects.stream().map(subject -> {
            SubjectVM vm = modelMapper.map(subject, SubjectVM.class);
            vm.setId(String.valueOf(subject.getId()));
            return vm;
        }).collect(Collectors.toList());

        ExamPaperBootstrapResponseVM response = new ExamPaperBootstrapResponseVM();
        response.setSubjects(subjectVMS);
        if (subjects.isEmpty()) {
            response.setActiveSubjectId(null);
            response.setPage(emptyPage(model.getPageIndex(), model.getPageSize()));
            return RestResponse.ok(response);
        }

        Integer activeSubjectId = subjects.get(0).getId();
        ExamPaperPageVM pageRequest = new ExamPaperPageVM();
        pageRequest.setPaperType(model.getPaperType());
        pageRequest.setSubjectId(activeSubjectId);
        pageRequest.setPageIndex(model.getPageIndex());
        pageRequest.setPageSize(model.getPageSize());
        response.setActiveSubjectId(activeSubjectId);
        response.setPage(toPageResponse(examPaperService.studentPage(pageRequest)));
        return RestResponse.ok(response);
    }

    private PageInfo<ExamPaperPageResponseVM> toPageResponse(PageInfo<ExamPaper> pageInfo) {
        return PageInfoHelper.copyMap(pageInfo, e -> {
            ExamPaperPageResponseVM vm = modelMapper.map(e, ExamPaperPageResponseVM.class);
            vm.setCreateTime(DateTimeUtil.dateFormat(e.getCreateTime()));
            return vm;
        });
    }

    private PageInfo<ExamPaperPageResponseVM> emptyPage(Integer pageIndex, Integer pageSize) {
        PageInfo<ExamPaperPageResponseVM> page = new PageInfo<>(Collections.emptyList());
        page.setPageNum(pageIndex);
        page.setPageSize(pageSize);
        return page;
    }
}
