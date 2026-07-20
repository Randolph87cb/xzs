package com.mindskip.xzs.controller.student;

import com.mindskip.xzs.base.BaseApiController;
import com.mindskip.xzs.base.RestResponse;
import com.mindskip.xzs.domain.*;
import com.mindskip.xzs.domain.enums.ExamPaperAnswerStatusEnum;
import com.mindskip.xzs.event.CalculateExamPaperAnswerCompleteEvent;
import com.mindskip.xzs.event.UserEvent;
import com.mindskip.xzs.service.ExamPaperAnswerService;
import com.mindskip.xzs.service.ExamPaperService;
import com.mindskip.xzs.service.SubjectService;
import com.mindskip.xzs.utility.DateTimeUtil;
import com.mindskip.xzs.utility.ExamUtil;
import com.mindskip.xzs.utility.PageInfoHelper;
import com.mindskip.xzs.viewmodel.admin.exam.ExamPaperEditRequestVM;
import com.mindskip.xzs.viewmodel.student.exam.ExamPaperReadVM;
import com.mindskip.xzs.viewmodel.student.exam.ExamPaperSubmitVM;
import com.mindskip.xzs.viewmodel.student.exampaper.ExamPaperAnswerPageResponseVM;
import com.mindskip.xzs.viewmodel.student.exampaper.ExamPaperAnswerPageVM;
import com.mindskip.xzs.viewmodel.student.exampaper.ExamPaperAnswerHistoryItemVM;
import com.mindskip.xzs.viewmodel.student.exampaper.ExamPaperAnswerHistoryVM;
import com.github.pagehelper.PageInfo;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.web.bind.annotation.*;

import javax.validation.Valid;
import java.util.Comparator;
import java.util.Date;
import java.util.List;
import java.util.stream.Collectors;

@RestController("StudentExamPaperAnswerController")
@RequestMapping(value = "/api/student/exampaper/answer")
public class ExamPaperAnswerController extends BaseApiController {

    private final ExamPaperAnswerService examPaperAnswerService;
    private final ExamPaperService examPaperService;
    private final SubjectService subjectService;
    private final ApplicationEventPublisher eventPublisher;

    @Autowired
    public ExamPaperAnswerController(ExamPaperAnswerService examPaperAnswerService, ExamPaperService examPaperService, SubjectService subjectService, ApplicationEventPublisher eventPublisher) {
        this.examPaperAnswerService = examPaperAnswerService;
        this.examPaperService = examPaperService;
        this.subjectService = subjectService;
        this.eventPublisher = eventPublisher;
    }


    @RequestMapping(value = "/pageList", method = RequestMethod.POST)
    public RestResponse<PageInfo<ExamPaperAnswerPageResponseVM>> pageList(@RequestBody @Valid ExamPaperAnswerPageVM model) {
        model.setCreateUser(getCurrentUser().getId());
        PageInfo<ExamPaperAnswer> pageInfo = examPaperAnswerService.studentPage(model);
        PageInfo<ExamPaperAnswerPageResponseVM> page = PageInfoHelper.copyMap(pageInfo, e -> {
            ExamPaperAnswerPageResponseVM vm = modelMapper.map(e, ExamPaperAnswerPageResponseVM.class);
            Subject subject = subjectService.selectById(vm.getSubjectId());
            vm.setDoTime(ExamUtil.secondToVM(e.getDoTime()));
            vm.setSystemScore(ExamUtil.scoreToVM(e.getSystemScore()));
            vm.setUserScore(ExamUtil.scoreToVM(e.getUserScore()));
            vm.setPaperScore(ExamUtil.scoreToVM(e.getPaperScore()));
            vm.setSubjectName(subject.getName());
            vm.setCreateTime(DateTimeUtil.dateFormat(e.getCreateTime()));
            return vm;
        });
        return RestResponse.ok(page);
    }


    @RequestMapping(value = "/answerSubmit", method = RequestMethod.POST)
    public RestResponse answerSubmit(@RequestBody @Valid ExamPaperSubmitVM examPaperSubmitVM) {
        User user = getCurrentUser();
        ExamPaperAnswerInfo examPaperAnswerInfo = examPaperAnswerService.calculateExamPaperAnswer(examPaperSubmitVM, user);
        if (null == examPaperAnswerInfo) {
            return RestResponse.fail(2, "试卷不能重复做");
        }
        ExamPaperAnswer examPaperAnswer = examPaperAnswerInfo.getExamPaperAnswer();
        Integer userScore = examPaperAnswer.getUserScore();
        String scoreVm = ExamUtil.scoreToVM(userScore);
        UserEventLog userEventLog = new UserEventLog(user.getId(), user.getUserName(), user.getRealName(), new Date());
        String content = user.getUserName() + " 提交试卷：" + examPaperAnswerInfo.getExamPaper().getName()
                + " 得分：" + scoreVm
                + " 耗时：" + ExamUtil.secondToVM(examPaperAnswer.getDoTime());
        userEventLog.setContent(content);
        eventPublisher.publishEvent(new CalculateExamPaperAnswerCompleteEvent(examPaperAnswerInfo));
        eventPublisher.publishEvent(new UserEvent(userEventLog));
        return RestResponse.ok(scoreVm);
    }


    @RequestMapping(value = "/edit", method = RequestMethod.POST)
    public RestResponse edit(@RequestBody @Valid ExamPaperSubmitVM examPaperSubmitVM) {
        ExamPaperAnswer examPaperAnswer = examPaperAnswerService.selectById(examPaperSubmitVM.getId());
        if (examPaperAnswer == null || !getCurrentUser().getId().equals(examPaperAnswer.getCreateUser())) {
            return RestResponse.fail(2, "答卷不存在或无权限访问");
        }

        boolean notJudge = examPaperSubmitVM.getAnswerItems().stream().anyMatch(i -> i.getDoRight() == null && i.getScore() == null);
        if (notJudge) {
            return RestResponse.fail(2, "有未批改题目");
        }

        ExamPaperAnswerStatusEnum examPaperAnswerStatusEnum = ExamPaperAnswerStatusEnum.fromCode(examPaperAnswer.getStatus());
        if (examPaperAnswerStatusEnum == ExamPaperAnswerStatusEnum.Complete) {
            return RestResponse.fail(3, "试卷已完成");
        }
        String score = examPaperAnswerService.judge(examPaperSubmitVM);
        User user = getCurrentUser();
        UserEventLog userEventLog = new UserEventLog(user.getId(), user.getUserName(), user.getRealName(), new Date());
        String content = user.getUserName() + " 批改试卷：" + examPaperAnswer.getPaperName() + " 得分：" + score;
        userEventLog.setContent(content);
        eventPublisher.publishEvent(new UserEvent(userEventLog));
        return RestResponse.ok(score);
    }

    @RequestMapping(value = "/read/{id}", method = RequestMethod.POST)
    public RestResponse<ExamPaperReadVM> read(@PathVariable Integer id) {
        ExamPaperAnswer examPaperAnswer = examPaperAnswerService.selectById(id);
        if (examPaperAnswer == null || !getCurrentUser().getId().equals(examPaperAnswer.getCreateUser())) {
            return RestResponse.fail(2, "答卷不存在或无权限访问");
        }
        ExamPaperReadVM vm = new ExamPaperReadVM();
        ExamPaperEditRequestVM paper = examPaperService.examPaperToVM(examPaperAnswer.getExamPaperId());
        ExamPaperSubmitVM answer = examPaperAnswerService.examPaperAnswerToVM(examPaperAnswer.getId());
        vm.setPaper(paper);
        vm.setAnswer(answer);
        return RestResponse.ok(vm);
    }

    @RequestMapping(value = "/paperHistory/{paperId}", method = RequestMethod.POST)
    public RestResponse<ExamPaperAnswerHistoryVM> paperHistory(@PathVariable Integer paperId) {
        List<ExamPaperAnswer> answers = examPaperAnswerService.selectPaperHistory(paperId, getCurrentUser().getId());
        ExamPaperAnswerHistoryVM vm = new ExamPaperAnswerHistoryVM();
        vm.setExamPaperId(paperId);
        vm.setAttemptCount(answers.size());
        vm.setItems(answers.stream().map(this::toHistoryItem).collect(Collectors.toList()));
        if (answers.isEmpty()) {
            vm.setBestScore("0");
            vm.setLatestScore("0");
            vm.setAverageScore("0");
            return RestResponse.ok(vm);
        }

        ExamPaperAnswer latest = answers.get(0);
        ExamPaperAnswer best = answers.stream().max(Comparator.comparing(this::safeScore)).orElse(latest);
        int averageScore = Math.round((float) answers.stream().mapToInt(this::safeScore).sum() / answers.size());
        vm.setBestScore(ExamUtil.scoreToVM(safeScore(best)));
        vm.setLatestScore(ExamUtil.scoreToVM(safeScore(latest)));
        vm.setAverageScore(ExamUtil.scoreToVM(averageScore));
        return RestResponse.ok(vm);
    }

    private ExamPaperAnswerHistoryItemVM toHistoryItem(ExamPaperAnswer answer) {
        ExamPaperAnswerHistoryItemVM vm = modelMapper.map(answer, ExamPaperAnswerHistoryItemVM.class);
        vm.setCreateTime(DateTimeUtil.dateFormat(answer.getCreateTime()));
        vm.setDoTime(ExamUtil.secondToVM(answer.getDoTime() == null ? 0 : answer.getDoTime()));
        vm.setSystemScore(ExamUtil.scoreToVM(safeScore(answer.getSystemScore())));
        vm.setUserScore(ExamUtil.scoreToVM(safeScore(answer.getUserScore())));
        vm.setPaperScore(ExamUtil.scoreToVM(safeScore(answer.getPaperScore())));
        return vm;
    }

    private Integer safeScore(ExamPaperAnswer answer) {
        return safeScore(answer.getUserScore());
    }

    private Integer safeScore(Integer score) {
        return score == null ? 0 : score;
    }

}
