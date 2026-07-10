package com.mindskip.xzs.controller.student;

import com.mindskip.xzs.base.BaseApiController;
import com.mindskip.xzs.base.RestResponse;
import com.mindskip.xzs.domain.ExamPaper;
import com.mindskip.xzs.domain.TaskExam;
import com.mindskip.xzs.domain.TaskExamCustomerAnswer;
import com.mindskip.xzs.domain.TextContent;
import com.mindskip.xzs.domain.User;
import com.mindskip.xzs.domain.enums.ExamPaperTypeEnum;
import com.mindskip.xzs.domain.task.TaskItemAnswerObject;
import com.mindskip.xzs.domain.task.TaskItemObject;
import com.mindskip.xzs.service.*;
import com.mindskip.xzs.utility.DateTimeUtil;
import com.mindskip.xzs.utility.JsonUtil;
import com.mindskip.xzs.viewmodel.student.dashboard.*;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestMethod;
import org.springframework.web.bind.annotation.RestController;

import java.util.ArrayList;
import java.util.Collections;
import java.util.Date;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.function.Function;
import java.util.stream.Collectors;

@RestController("StudentDashboardController")
@RequestMapping(value = "/api/student/dashboard")
public class DashboardController extends BaseApiController {

    private final UserService userService;
    private final ExamPaperService examPaperService;
    private final QuestionService questionService;
    private final TaskExamService taskExamService;
    private final TaskExamCustomerAnswerService taskExamCustomerAnswerService;
    private final TextContentService textContentService;

    @Autowired
    public DashboardController(UserService userService, ExamPaperService examPaperService, QuestionService questionService, TaskExamService taskExamService, TaskExamCustomerAnswerService taskExamCustomerAnswerService, TextContentService textContentService) {
        this.userService = userService;
        this.examPaperService = examPaperService;
        this.questionService = questionService;
        this.taskExamService = taskExamService;
        this.taskExamCustomerAnswerService = taskExamCustomerAnswerService;
        this.textContentService = textContentService;
    }

    @RequestMapping(value = "/index", method = RequestMethod.POST)
    public RestResponse<IndexVM> index() {
        User user = getCurrentUser();
        IndexVM indexVM = new IndexVM();

        PaperFilter fixedPaperFilter = new PaperFilter();
        fixedPaperFilter.setExamPaperType(ExamPaperTypeEnum.Fixed.getCode());
        fixedPaperFilter.setSubjectId(user.getTargetSubjectId());
        indexVM.setFixedPaper(examPaperService.indexPaper(fixedPaperFilter));

        PaperFilter timeLimitPaperFilter = new PaperFilter();
        timeLimitPaperFilter.setDateTime(new Date());
        timeLimitPaperFilter.setExamPaperType(ExamPaperTypeEnum.TimeLimit.getCode());
        timeLimitPaperFilter.setSubjectId(user.getTargetSubjectId());

        List<PaperInfo> limitPaper = examPaperService.indexPaper(timeLimitPaperFilter);
        List<PaperInfoVM> paperInfoVMS = limitPaper.stream().map(d -> {
            PaperInfoVM vm = modelMapper.map(d, PaperInfoVM.class);
            vm.setStartTime(DateTimeUtil.dateFormat(d.getLimitStartTime()));
            vm.setEndTime(DateTimeUtil.dateFormat(d.getLimitEndTime()));
            return vm;
        }).collect(Collectors.toList());
        indexVM.setTimeLimitPaper(paperInfoVMS);
        return RestResponse.ok(indexVM);
    }


    @RequestMapping(value = "/task", method = RequestMethod.POST)
    public RestResponse<List<TaskItemVm>> task() {
        User user = getCurrentUser();
        List<TaskExam> taskExams = taskExamService.getByGradeLevelOrClass(user.getUserLevel(), user.getClassId());
        if (taskExams.size() == 0) {
            return RestResponse.ok(new ArrayList<>());
        }
        List<Integer> tIds = taskExams.stream().map(taskExam -> taskExam.getId()).collect(Collectors.toList());
        List<TaskExamCustomerAnswer> taskExamCustomerAnswers = taskExamCustomerAnswerService.selectByTUid(tIds, user.getId());
        Map<Integer, TaskExamCustomerAnswer> taskAnswerMap = taskExamCustomerAnswers.stream()
                .collect(Collectors.toMap(TaskExamCustomerAnswer::getTaskExamId, Function.identity(), (a, b) -> a));
        List<TaskPaperContext> taskPaperContexts = taskExams.stream()
                .map(t -> new TaskPaperContext(t, getTaskPaperItems(t.getFrameTextContentId())))
                .collect(Collectors.toList());
        Map<Integer, ExamPaper> examPaperMap = getTaskExamPaperMap(taskPaperContexts, user.getTargetSubjectId());
        List<TaskItemVm> vm = taskPaperContexts.stream().map(context -> {
            TaskExam t = context.getTaskExam();
            TaskItemVm itemVm = new TaskItemVm();
            itemVm.setId(t.getId());
            itemVm.setTitle(t.getTitle());
            TaskExamCustomerAnswer taskExamCustomerAnswer = taskAnswerMap.get(t.getId());
            List<TaskItemPaperVm> paperItemVMS = getTaskItemPaperVm(context.getPaperItems(), taskExamCustomerAnswer, user.getTargetSubjectId(), examPaperMap);
            itemVm.setPaperItems(paperItemVMS);
            return itemVm;
        }).filter(item -> user.getTargetSubjectId() == null || !item.getPaperItems().isEmpty()).collect(Collectors.toList());
        return RestResponse.ok(vm);
    }

    @RequestMapping(value = "/class/ranking", method = RequestMethod.POST)
    public RestResponse<List<ClassRankingVM>> classRanking() {
        User user = getCurrentUser();
        if (user.getClassId() == null) {
            return RestResponse.ok(Collections.emptyList());
        }
        List<ClassRankingVM> ranking = userService.classRanking(user.getClassId()).stream()
                .map(ClassRankingVM::from)
                .collect(Collectors.toList());
        return RestResponse.ok(ranking);
    }


    private List<TaskItemObject> getTaskPaperItems(Integer tFrameId) {
        TextContent textContent = textContentService.selectById(tFrameId);
        return JsonUtil.toJsonListObject(textContent.getContent(), TaskItemObject.class);
    }

    private Map<Integer, ExamPaper> getTaskExamPaperMap(List<TaskPaperContext> taskPaperContexts, Integer targetSubjectId) {
        if (targetSubjectId == null) {
            return Collections.emptyMap();
        }
        Set<Integer> paperIds = new HashSet<>();
        taskPaperContexts.forEach(context -> context.getPaperItems()
                .forEach(item -> paperIds.add(item.getExamPaperId())));
        if (paperIds.isEmpty()) {
            return Collections.emptyMap();
        }
        return examPaperService.selectByIds(new ArrayList<>(paperIds)).stream()
                .collect(Collectors.toMap(ExamPaper::getId, Function.identity(), (a, b) -> a));
    }

    private List<TaskItemPaperVm> getTaskItemPaperVm(List<TaskItemObject> paperItems, TaskExamCustomerAnswer taskExamCustomerAnswers, Integer targetSubjectId, Map<Integer, ExamPaper> examPaperMap) {
        List<TaskItemAnswerObject> answerPaperItems = null;
        if (null != taskExamCustomerAnswers) {
            TextContent answerTextContent = textContentService.selectById(taskExamCustomerAnswers.getTextContentId());
            answerPaperItems = JsonUtil.toJsonListObject(answerTextContent.getContent(), TaskItemAnswerObject.class);
        }


        List<TaskItemAnswerObject> finalAnswerPaperItems = answerPaperItems;
        return paperItems.stream().filter(p -> {
                    if (targetSubjectId == null) {
                        return true;
                    }
                    ExamPaper examPaper = examPaperMap.get(p.getExamPaperId());
                    return examPaper != null && targetSubjectId.equals(examPaper.getSubjectId());
                }).map(p -> {
                    TaskItemPaperVm ivm = new TaskItemPaperVm();
                    ivm.setExamPaperId(p.getExamPaperId());
                    ivm.setExamPaperName(p.getExamPaperName());
                    if (null != finalAnswerPaperItems) {
                        finalAnswerPaperItems.stream()
                                .filter(a -> a.getExamPaperId().equals(p.getExamPaperId()))
                                .findFirst()
                                .ifPresent(a -> {
                                    ivm.setExamPaperAnswerId(a.getExamPaperAnswerId());
                                    ivm.setStatus(a.getStatus());
                                });
                    }
                    return ivm;
                }
        ).collect(Collectors.toList());
    }

    private static class TaskPaperContext {
        private final TaskExam taskExam;
        private final List<TaskItemObject> paperItems;

        TaskPaperContext(TaskExam taskExam, List<TaskItemObject> paperItems) {
            this.taskExam = taskExam;
            this.paperItems = paperItems;
        }

        TaskExam getTaskExam() {
            return taskExam;
        }

        List<TaskItemObject> getPaperItems() {
            return paperItems;
        }
    }
}
