package com.mindskip.xzs.controller.admin;

import com.mindskip.xzs.base.BaseApiController;
import com.mindskip.xzs.base.RestResponse;
import com.mindskip.xzs.base.SystemCode;
import com.mindskip.xzs.domain.Question;
import com.mindskip.xzs.domain.Subject;
import com.mindskip.xzs.domain.TextContent;
import com.mindskip.xzs.domain.enums.QuestionTypeEnum;
import com.mindskip.xzs.domain.question.QuestionObject;
import com.mindskip.xzs.service.QuestionService;
import com.mindskip.xzs.service.SubjectService;
import com.mindskip.xzs.service.TextContentService;
import com.mindskip.xzs.utility.*;
import com.mindskip.xzs.viewmodel.admin.question.QuestionEditRequestVM;
import com.mindskip.xzs.viewmodel.admin.question.QuestionImportResultVM;
import com.mindskip.xzs.viewmodel.admin.question.QuestionPageRequestVM;
import com.mindskip.xzs.viewmodel.admin.question.QuestionResponseVM;
import com.github.pagehelper.PageInfo;
import org.apache.commons.lang3.StringUtils;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.MediaType;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import javax.validation.Valid;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;

@RestController("AdminQuestionController")
@RequestMapping(value = "/api/admin/question")
public class QuestionController extends BaseApiController {

    private final QuestionService questionService;
    private final TextContentService textContentService;
    private final SubjectService subjectService;

    @Autowired
    public QuestionController(QuestionService questionService, TextContentService textContentService, SubjectService subjectService) {
        this.questionService = questionService;
        this.textContentService = textContentService;
        this.subjectService = subjectService;
    }

    @RequestMapping(value = "/page", method = RequestMethod.POST)
    public RestResponse<PageInfo<QuestionResponseVM>> pageList(@RequestBody QuestionPageRequestVM model) {
        PageInfo<Question> pageInfo = questionService.page(model);
        PageInfo<QuestionResponseVM> page = PageInfoHelper.copyMap(pageInfo, q -> {
            QuestionResponseVM vm = modelMapper.map(q, QuestionResponseVM.class);
            vm.setCreateTime(DateTimeUtil.dateFormat(q.getCreateTime()));
            vm.setScore(ExamUtil.scoreToVM(q.getScore()));
            TextContent textContent = textContentService.selectById(q.getInfoTextContentId());
            QuestionObject questionObject = JsonUtil.toJsonObject(textContent.getContent(), QuestionObject.class);
            String clearHtml = HtmlUtil.clear(questionObject.getTitleContent());
            vm.setShortTitle(clearHtml);
            return vm;
        });
        return RestResponse.ok(page);
    }

    @RequestMapping(value = "/edit", method = RequestMethod.POST)
    public RestResponse edit(@RequestBody @Valid QuestionEditRequestVM model) {
        RestResponse validQuestionEditRequestResult = validQuestionEditRequestVM(model);
        if (validQuestionEditRequestResult.getCode() != SystemCode.OK.getCode()) {
            return validQuestionEditRequestResult;
        }

        if (null == model.getId()) {
            questionService.insertFullQuestion(model, getCurrentUser().getId());
        } else {
            questionService.updateFullQuestion(model);
        }

        return RestResponse.ok();
    }

    @RequestMapping(value = "/select/{id}", method = RequestMethod.POST)
    public RestResponse<QuestionEditRequestVM> select(@PathVariable Integer id) {
        QuestionEditRequestVM newVM = questionService.getQuestionEditRequestVM(id);
        return RestResponse.ok(newVM);
    }


    @RequestMapping(value = "/delete/{id}", method = RequestMethod.POST)
    public RestResponse delete(@PathVariable Integer id) {
        Question question = questionService.selectById(id);
        question.setDeleted(true);
        questionService.updateByIdFilter(question);
        return RestResponse.ok();
    }

    @RequestMapping(value = "/import/markdown", method = RequestMethod.POST, consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    @Transactional
    public RestResponse<QuestionImportResultVM> importMarkdown(@RequestParam("file") MultipartFile file,
                                                              @RequestParam Integer subjectId,
                                                              @RequestParam(defaultValue = "1") String score,
                                                              @RequestParam(defaultValue = "1") Integer difficult,
                                                              @RequestParam(required = false, defaultValue = "综合") String knowledgePoint,
                                                              @RequestParam(required = false, defaultValue = "暂无解析") String analyze) {
        if (file == null || file.isEmpty()) {
            return RestResponse.fail(2, "Markdown 文件不能为空");
        }

        Subject subject = subjectService.selectById(subjectId);
        if (subject == null || Boolean.TRUE.equals(subject.getDeleted())) {
            return RestResponse.fail(2, "学科不存在");
        }

        if (StringUtils.isBlank(score)) {
            return RestResponse.fail(2, "分数不能为空");
        }

        if (difficult == null || difficult < 1 || difficult > 5) {
            return RestResponse.fail(2, "难度必须在 1 到 5 之间");
        }

        String markdown;
        try {
            markdown = new String(file.getBytes(), StandardCharsets.UTF_8);
        } catch (IOException e) {
            return RestResponse.fail(2, "读取 Markdown 文件失败：" + e.getMessage());
        }

        List<MarkdownQuestionImportUtil.MarkdownQuestion> markdownQuestions;
        try {
            markdownQuestions = MarkdownQuestionImportUtil.parseSingleChoice(markdown, analyze);
        } catch (IllegalArgumentException e) {
            return RestResponse.fail(2, e.getMessage());
        }

        List<QuestionEditRequestVM> requestVMS = new ArrayList<>();
        for (MarkdownQuestionImportUtil.MarkdownQuestion markdownQuestion : markdownQuestions) {
            QuestionEditRequestVM requestVM = new QuestionEditRequestVM();
            requestVM.setQuestionType(QuestionTypeEnum.SingleChoice.getCode());
            requestVM.setSubjectId(subjectId);
            requestVM.setTitle(markdownQuestion.getTitle());
            requestVM.setItems(markdownQuestion.getItems());
            requestVM.setAnalyze(markdownQuestion.getAnalyze());
            requestVM.setCorrect(markdownQuestion.getCorrect());
            requestVM.setScore(score);
            requestVM.setDifficult(difficult);
            requestVM.setKnowledgePoint(knowledgePoint);

            RestResponse validResult = validQuestionEditRequestVM(requestVM);
            if (validResult.getCode() != SystemCode.OK.getCode()) {
                return RestResponse.fail(validResult.getCode(), "第" + markdownQuestion.getOrder() + "题：" + validResult.getMessage());
            }
            requestVMS.add(requestVM);
        }

        List<Integer> questionIds = new ArrayList<>();
        for (QuestionEditRequestVM requestVM : requestVMS) {
            Question question = questionService.insertFullQuestion(requestVM, getCurrentUser().getId());
            questionIds.add(question.getId());
        }

        return RestResponse.ok(new QuestionImportResultVM(markdownQuestions.size(), questionIds.size(), questionIds));
    }

    private RestResponse validQuestionEditRequestVM(QuestionEditRequestVM model) {
        int qType = model.getQuestionType().intValue();
        boolean requireCorrect = qType == QuestionTypeEnum.SingleChoice.getCode() || qType == QuestionTypeEnum.TrueFalse.getCode();
        if (requireCorrect) {
            if (StringUtils.isBlank(model.getCorrect())) {
                String errorMsg = ErrorUtil.parameterErrorFormat("correct", "不能为空");
                return new RestResponse<>(SystemCode.ParameterValidError.getCode(), errorMsg);
            }
        }

        if (qType == QuestionTypeEnum.GapFilling.getCode()) {
            Integer fillSumScore = model.getItems().stream().mapToInt(d -> ExamUtil.scoreFromVM(d.getScore())).sum();
            Integer questionScore = ExamUtil.scoreFromVM(model.getScore());
            if (!fillSumScore.equals(questionScore)) {
                String errorMsg = ErrorUtil.parameterErrorFormat("score", "空分数和与题目总分不相等");
                return new RestResponse<>(SystemCode.ParameterValidError.getCode(), errorMsg);
            }
        }
        return RestResponse.ok();
    }
}
