package com.mindskip.xzs.service.impl;

import com.mindskip.xzs.domain.*;
import com.mindskip.xzs.domain.ExamPaper;
import com.mindskip.xzs.domain.Question;
import com.mindskip.xzs.domain.TextContent;
import com.mindskip.xzs.domain.enums.ExamPaperTypeEnum;
import com.mindskip.xzs.domain.enums.QuestionTypeEnum;
import com.mindskip.xzs.domain.exam.ExamPaperQuestionItemObject;
import com.mindskip.xzs.domain.exam.ExamPaperTitleItemObject;
import com.mindskip.xzs.domain.other.KeyValue;
import com.mindskip.xzs.repository.ExamPaperMapper;
import com.mindskip.xzs.repository.QuestionMapper;
import com.mindskip.xzs.service.ExamPaperService;
import com.mindskip.xzs.service.QuestionService;
import com.mindskip.xzs.service.SmartTrainingConfigService;
import com.mindskip.xzs.service.SubjectService;
import com.mindskip.xzs.service.TextContentService;
import com.mindskip.xzs.service.enums.ActionEnum;
import com.mindskip.xzs.utility.DateTimeUtil;
import com.mindskip.xzs.utility.JsonUtil;
import com.mindskip.xzs.utility.ModelMapperSingle;
import com.mindskip.xzs.utility.ExamUtil;
import com.mindskip.xzs.viewmodel.admin.exam.ExamPaperEditRequestVM;
import com.mindskip.xzs.viewmodel.admin.exam.ExamPaperPageRequestVM;
import com.mindskip.xzs.viewmodel.admin.exam.ExamPaperTitleItemVM;
import com.mindskip.xzs.viewmodel.admin.question.QuestionEditRequestVM;
import com.mindskip.xzs.viewmodel.admin.smarttraining.SmartTrainingRuleVM;
import com.mindskip.xzs.viewmodel.student.dashboard.PaperFilter;
import com.mindskip.xzs.viewmodel.student.dashboard.PaperInfo;
import com.mindskip.xzs.viewmodel.student.exam.ExamPaperPageVM;
import com.github.pagehelper.PageHelper;
import com.github.pagehelper.PageInfo;
import com.mindskip.xzs.domain.User;
import org.modelmapper.ModelMapper;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.Date;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Collectors;

@Service
public class ExamPaperServiceImpl extends BaseServiceImpl<ExamPaper> implements ExamPaperService {

    protected final static ModelMapper modelMapper = ModelMapperSingle.Instance();
    private static final int SMART_TRAINING_QUESTION_LIMIT = 20;
    private static final int SMART_TRAINING_SUGGEST_TIME = 30;
    private static final int GESP_OBJECTIVE_SUGGEST_TIME = 60;
    private static final Pattern GESP_IMPORT_SOURCE_PATTERN = Pattern.compile("^(\\d{4})-(\\d{2})/C\\+\\+-(\\d+)/(选择题|判断题)\\.md$");
    private final ExamPaperMapper examPaperMapper;
    private final QuestionMapper questionMapper;
    private final TextContentService textContentService;
    private final QuestionService questionService;
    private final SubjectService subjectService;
    private final SmartTrainingConfigService smartTrainingConfigService;
    private final JdbcTemplate jdbcTemplate;

    @Autowired
    public ExamPaperServiceImpl(ExamPaperMapper examPaperMapper, QuestionMapper questionMapper, TextContentService textContentService, QuestionService questionService, SubjectService subjectService, SmartTrainingConfigService smartTrainingConfigService, JdbcTemplate jdbcTemplate) {
        super(examPaperMapper);
        this.examPaperMapper = examPaperMapper;
        this.questionMapper = questionMapper;
        this.textContentService = textContentService;
        this.questionService = questionService;
        this.subjectService = subjectService;
        this.smartTrainingConfigService = smartTrainingConfigService;
        this.jdbcTemplate = jdbcTemplate;
    }


    @Override
    public PageInfo<ExamPaper> page(ExamPaperPageRequestVM requestVM) {
        return PageHelper.startPage(requestVM.getPageIndex(), requestVM.getPageSize(), "id desc").doSelectPageInfo(() ->
                examPaperMapper.page(requestVM));
    }

    @Override
    public PageInfo<ExamPaper> taskExamPage(ExamPaperPageRequestVM requestVM) {
        return PageHelper.startPage(requestVM.getPageIndex(), requestVM.getPageSize(), "id desc").doSelectPageInfo(() ->
                examPaperMapper.taskExamPage(requestVM));
    }

    @Override
    public PageInfo<ExamPaper> studentPage(ExamPaperPageVM requestVM) {
        return PageHelper.startPage(requestVM.getPageIndex(), requestVM.getPageSize(), "id desc").doSelectPageInfo(() ->
                examPaperMapper.studentPage(requestVM));
    }


    @Override
    @Transactional
    public ExamPaper savePaperFromVM(ExamPaperEditRequestVM examPaperEditRequestVM, User user) {
        ActionEnum actionEnum = (examPaperEditRequestVM.getId() == null) ? ActionEnum.ADD : ActionEnum.UPDATE;
        Date now = new Date();
        List<ExamPaperTitleItemVM> titleItemsVM = examPaperEditRequestVM.getTitleItems();
        List<ExamPaperTitleItemObject> frameTextContentList = frameTextContentFromVM(titleItemsVM);
        String frameTextContentStr = JsonUtil.toJsonStr(frameTextContentList);

        ExamPaper examPaper;
        if (actionEnum == ActionEnum.ADD) {
            examPaper = modelMapper.map(examPaperEditRequestVM, ExamPaper.class);
            TextContent frameTextContent = new TextContent(frameTextContentStr, now);
            textContentService.insertByFilter(frameTextContent);
            examPaper.setFrameTextContentId(frameTextContent.getId());
            examPaper.setCreateTime(now);
            examPaper.setCreateUser(user.getId());
            examPaper.setDeleted(false);
            examPaperFromVM(examPaperEditRequestVM, examPaper, titleItemsVM);
            examPaperMapper.insertSelective(examPaper);
        } else {
            examPaper = examPaperMapper.selectByPrimaryKey(examPaperEditRequestVM.getId());
            TextContent frameTextContent = textContentService.selectById(examPaper.getFrameTextContentId());
            frameTextContent.setContent(frameTextContentStr);
            textContentService.updateByIdFilter(frameTextContent);
            modelMapper.map(examPaperEditRequestVM, examPaper);
            examPaperFromVM(examPaperEditRequestVM, examPaper, titleItemsVM);
            examPaperMapper.updateByPrimaryKeySelective(examPaper);
        }
        return examPaper;
    }

    @Override
    @Transactional
    public ExamPaper createSmartTrainingPaper(Integer subjectId, User user) {
        Subject subject = subjectService.selectById(subjectId);
        if (subject == null) {
            throw new IllegalArgumentException("科目不存在");
        }

        List<Question> questions = selectSmartTrainingQuestions(subjectId);
        if (questions == null || questions.isEmpty()) {
            throw new IllegalArgumentException("当前科目暂无可用题目");
        }

        Date now = new Date();
        List<ExamPaperTitleItemObject> titleItems = frameTextContentFromQuestions(questions);
        TextContent frameTextContent = new TextContent(JsonUtil.toJsonStr(titleItems), now);
        textContentService.insertByFilter(frameTextContent);

        ExamPaper examPaper = new ExamPaper();
        examPaper.setName("智能训练-" + subject.getName() + "-" + DateTimeUtil.dateFormat(now));
        examPaper.setSubjectId(subjectId);
        examPaper.setPaperType(ExamPaperTypeEnum.SmartTraining.getCode());
        examPaper.setGradeLevel(subject.getLevel());
        examPaper.setScore(questions.stream().mapToInt(Question::getScore).sum());
        examPaper.setQuestionCount(questions.size());
        examPaper.setSuggestTime(SMART_TRAINING_SUGGEST_TIME);
        examPaper.setFrameTextContentId(frameTextContent.getId());
        examPaper.setCreateUser(user.getId());
        examPaper.setCreateTime(now);
        examPaper.setDeleted(false);
        examPaperMapper.insertSelective(examPaper);
        return examPaper;
    }

    @Override
    @Transactional
    public List<ExamPaper> importGespObjectivePapers(User user) {
        List<ImportedGespQuestion> importedQuestions = selectImportedGespObjectiveQuestions();
        Map<String, GespPaperGroup> groups = new HashMap<>();
        for (ImportedGespQuestion importedQuestion : importedQuestions) {
            QuestionImportMetadata metadata = JsonUtil.toJsonObject(importedQuestion.getContent(), QuestionImportMetadata.class);
            if (metadata == null || !"GESP_OBJECTIVE_MD".equals(metadata.getImportBatch())) {
                continue;
            }

            String importSource = metadata.getImportSource() == null ? "" : metadata.getImportSource().replace("\\", "/");
            Matcher matcher = GESP_IMPORT_SOURCE_PATTERN.matcher(importSource);
            if (!matcher.matches() || metadata.getImportQuestionOrder() == null) {
                continue;
            }

            int year = Integer.parseInt(matcher.group(1));
            int month = Integer.parseInt(matcher.group(2));
            int level = Integer.parseInt(matcher.group(3));
            String kind = matcher.group(4);
            int order = metadata.getImportQuestionOrder();
            String key = year + "-" + month + "-" + level;
            GespPaperGroup group = groups.computeIfAbsent(key, k -> new GespPaperGroup(year, month, level));

            if ("选择题".equals(kind) && importedQuestion.getQuestionType() == QuestionTypeEnum.SingleChoice.getCode() && order >= 1 && order <= 15) {
                group.getChoiceQuestions().put(order, importedQuestion.getQuestion());
            } else if ("判断题".equals(kind) && importedQuestion.getQuestionType() == QuestionTypeEnum.TrueFalse.getCode() && order >= 1 && order <= 10) {
                group.getTrueFalseQuestions().put(order, importedQuestion.getQuestion());
            }
        }

        List<GespPaperGroup> completeGroups = groups.values().stream()
                .filter(GespPaperGroup::isComplete)
                .sorted(Comparator.comparingInt(GespPaperGroup::getYear)
                        .thenComparingInt(GespPaperGroup::getMonth)
                        .thenComparingInt(GespPaperGroup::getLevel))
                .collect(Collectors.toList());
        if (completeGroups.isEmpty()) {
            throw new IllegalStateException("未找到完整的GESP客观题组卷数据，请先导入真题题库。");
        }

        List<ExamPaper> importedPapers = new ArrayList<>();
        for (GespPaperGroup group : completeGroups) {
            ExamPaperEditRequestVM requestVM = buildGespObjectivePaperRequest(group);
            Integer existingPaperId = selectActiveFixedPaperIdByName(requestVM.getName());
            requestVM.setId(existingPaperId);
            importedPapers.add(savePaperFromVM(requestVM, user));
        }
        return importedPapers;
    }

    private List<ImportedGespQuestion> selectImportedGespObjectiveQuestions() {
        String sql = "select q.id, q.question_type, q.subject_id, q.score, q.grade_level, q.difficult, q.knowledge_point, " +
                "q.correct, q.info_text_content_id, q.create_user, q.status, q.create_time, q.deleted, tc.content " +
                "from t_question q join t_text_content tc on tc.id = q.info_text_content_id " +
                "where q.deleted = false and tc.content like '%\"importBatch\":\"GESP_OBJECTIVE_MD\"%' order by q.id";
        return jdbcTemplate.query(sql, (rs, rowNum) -> {
            Question question = new Question();
            question.setId(rs.getInt("id"));
            question.setQuestionType(rs.getInt("question_type"));
            question.setSubjectId(rs.getInt("subject_id"));
            question.setScore(rs.getInt("score"));
            question.setGradeLevel(rs.getInt("grade_level"));
            question.setDifficult(rs.getInt("difficult"));
            question.setKnowledgePoint(rs.getString("knowledge_point"));
            question.setCorrect(rs.getString("correct"));
            question.setInfoTextContentId(rs.getInt("info_text_content_id"));
            question.setCreateUser(rs.getInt("create_user"));
            question.setStatus(rs.getInt("status"));
            question.setCreateTime(rs.getTimestamp("create_time"));
            question.setDeleted(rs.getBoolean("deleted"));
            return new ImportedGespQuestion(question, rs.getString("content"));
        });
    }

    private ExamPaperEditRequestVM buildGespObjectivePaperRequest(GespPaperGroup group) {
        ExamPaperEditRequestVM requestVM = new ExamPaperEditRequestVM();
        requestVM.setLevel(group.getLevel());
        requestVM.setSubjectId(group.getLevel());
        requestVM.setPaperType(ExamPaperTypeEnum.Fixed.getCode());
        requestVM.setName(group.getTitle());
        requestVM.setSuggestTime(GESP_OBJECTIVE_SUGGEST_TIME);

        ExamPaperTitleItemVM choiceTitleItem = new ExamPaperTitleItemVM();
        choiceTitleItem.setName("选择题");
        choiceTitleItem.setQuestionItems(group.getChoiceQuestions().values().stream()
                .map(questionService::getQuestionEditRequestVM)
                .collect(Collectors.toList()));

        ExamPaperTitleItemVM trueFalseTitleItem = new ExamPaperTitleItemVM();
        trueFalseTitleItem.setName("判断题");
        trueFalseTitleItem.setQuestionItems(group.getTrueFalseQuestions().values().stream()
                .map(questionService::getQuestionEditRequestVM)
                .collect(Collectors.toList()));

        List<ExamPaperTitleItemVM> titleItems = new ArrayList<>();
        titleItems.add(choiceTitleItem);
        titleItems.add(trueFalseTitleItem);
        requestVM.setTitleItems(titleItems);
        return requestVM;
    }

    private Integer selectActiveFixedPaperIdByName(String paperName) {
        List<Integer> ids = jdbcTemplate.queryForList(
                "select id from t_exam_paper where name = ? and paper_type = ? and deleted = false order by id desc limit 1",
                Integer.class,
                paperName,
                ExamPaperTypeEnum.Fixed.getCode());
        return ids.isEmpty() ? null : ids.get(0);
    }

    private List<Question> selectSmartTrainingQuestions(Integer subjectId) {
        SmartTrainingConfig config = smartTrainingConfigService.selectBySubjectId(subjectId);
        if (config == null || config.getRuleJson() == null || config.getRuleJson().length() == 0) {
            return questionMapper.selectRandomBySubjectId(subjectId, SMART_TRAINING_QUESTION_LIMIT);
        }

        List<SmartTrainingRuleVM> rules = JsonUtil.toJsonListObject(config.getRuleJson(), SmartTrainingRuleVM.class);
        if (rules == null || rules.isEmpty()) {
            return questionMapper.selectRandomBySubjectId(subjectId, config.getQuestionCount());
        }

        List<Question> questions = new ArrayList<>();
        for (SmartTrainingRuleVM rule : rules) {
            Integer availableCount = questionMapper.selectCountBySubjectIdAndKnowledgePoint(subjectId, rule.getKnowledgePoint());
            if (availableCount == null || availableCount < rule.getQuestionCount()) {
                throw new IllegalArgumentException("知识点“" + rule.getKnowledgePoint() + "”可用题目不足，需要" + rule.getQuestionCount() + "题，当前" + (availableCount == null ? 0 : availableCount) + "题");
            }
            questions.addAll(questionMapper.selectRandomBySubjectIdAndKnowledgePoint(subjectId, rule.getKnowledgePoint(), rule.getQuestionCount()));
        }
        return questions;
    }

    @Override
    public ExamPaperEditRequestVM examPaperToVM(Integer id) {
        ExamPaper examPaper = examPaperMapper.selectByPrimaryKey(id);
        ExamPaperEditRequestVM vm = modelMapper.map(examPaper, ExamPaperEditRequestVM.class);
        vm.setLevel(examPaper.getGradeLevel());
        TextContent frameTextContent = textContentService.selectById(examPaper.getFrameTextContentId());
        List<ExamPaperTitleItemObject> examPaperTitleItemObjects = JsonUtil.toJsonListObject(frameTextContent.getContent(), ExamPaperTitleItemObject.class);
        List<Integer> questionIds = examPaperTitleItemObjects.stream()
                .flatMap(t -> t.getQuestionItems().stream()
                        .map(q -> q.getId()))
                .collect(Collectors.toList());
        List<Question> questions = questionMapper.selectByIds(questionIds);
        List<ExamPaperTitleItemVM> examPaperTitleItemVMS = examPaperTitleItemObjects.stream().map(t -> {
            ExamPaperTitleItemVM tTitleVM = modelMapper.map(t, ExamPaperTitleItemVM.class);
            List<QuestionEditRequestVM> questionItemsVM = t.getQuestionItems().stream().map(i -> {
                Question question = questions.stream().filter(q -> q.getId().equals(i.getId())).findFirst().get();
                QuestionEditRequestVM questionEditRequestVM = questionService.getQuestionEditRequestVM(question);
                questionEditRequestVM.setItemOrder(i.getItemOrder());
                return questionEditRequestVM;
            }).collect(Collectors.toList());
            tTitleVM.setQuestionItems(questionItemsVM);
            return tTitleVM;
        }).collect(Collectors.toList());
        vm.setTitleItems(examPaperTitleItemVMS);
        vm.setScore(ExamUtil.scoreToVM(examPaper.getScore()));
        if (ExamPaperTypeEnum.TimeLimit == ExamPaperTypeEnum.fromCode(examPaper.getPaperType())) {
            List<String> limitDateTime = Arrays.asList(DateTimeUtil.dateFormat(examPaper.getLimitStartTime()), DateTimeUtil.dateFormat(examPaper.getLimitEndTime()));
            vm.setLimitDateTime(limitDateTime);
        }
        return vm;
    }

    @Override
    public List<PaperInfo> indexPaper(PaperFilter paperFilter) {
        return examPaperMapper.indexPaper(paperFilter);
    }


    @Override
    public Integer selectAllCount() {
        return examPaperMapper.selectAllCount();
    }

    @Override
    public List<Integer> selectMothCount() {
        Date startTime = DateTimeUtil.getMonthStartDay();
        Date endTime = DateTimeUtil.getMonthEndDay();
        List<KeyValue> mouthCount = examPaperMapper.selectCountByDate(startTime, endTime);
        List<String> mothStartToNowFormat = DateTimeUtil.MothStartToNowFormat();
        return mothStartToNowFormat.stream().map(md -> {
            KeyValue keyValue = mouthCount.stream().filter(kv -> kv.getName().equals(md)).findAny().orElse(null);
            return null == keyValue ? 0 : keyValue.getValue();
        }).collect(Collectors.toList());
    }

    private void examPaperFromVM(ExamPaperEditRequestVM examPaperEditRequestVM, ExamPaper examPaper, List<ExamPaperTitleItemVM> titleItemsVM) {
        Integer gradeLevel = subjectService.levelBySubjectId(examPaperEditRequestVM.getSubjectId());
        Integer questionCount = titleItemsVM.stream()
                .mapToInt(t -> t.getQuestionItems().size()).sum();
        Integer score = titleItemsVM.stream().
                flatMapToInt(t -> t.getQuestionItems().stream()
                        .mapToInt(q -> ExamUtil.scoreFromVM(q.getScore()))
                ).sum();
        examPaper.setQuestionCount(questionCount);
        examPaper.setScore(score);
        examPaper.setGradeLevel(gradeLevel);
        List<String> dateTimes = examPaperEditRequestVM.getLimitDateTime();
        if (ExamPaperTypeEnum.TimeLimit == ExamPaperTypeEnum.fromCode(examPaper.getPaperType())) {
            examPaper.setLimitStartTime(DateTimeUtil.parse(dateTimes.get(0), DateTimeUtil.STANDER_FORMAT));
            examPaper.setLimitEndTime(DateTimeUtil.parse(dateTimes.get(1), DateTimeUtil.STANDER_FORMAT));
        }
    }

    private List<ExamPaperTitleItemObject> frameTextContentFromVM(List<ExamPaperTitleItemVM> titleItems) {
        AtomicInteger index = new AtomicInteger(1);
        return titleItems.stream().map(t -> {
            ExamPaperTitleItemObject titleItem = modelMapper.map(t, ExamPaperTitleItemObject.class);
            List<ExamPaperQuestionItemObject> questionItems = t.getQuestionItems().stream()
                    .map(q -> {
                        ExamPaperQuestionItemObject examPaperQuestionItemObject = modelMapper.map(q, ExamPaperQuestionItemObject.class);
                        examPaperQuestionItemObject.setItemOrder(index.getAndIncrement());
                        return examPaperQuestionItemObject;
                    })
                    .collect(Collectors.toList());
            titleItem.setQuestionItems(questionItems);
            return titleItem;
        }).collect(Collectors.toList());
    }

    private List<ExamPaperTitleItemObject> frameTextContentFromQuestions(List<Question> questions) {
        List<ExamPaperTitleItemObject> titleItems = new ArrayList<>();
        AtomicInteger itemOrder = new AtomicInteger(1);
        Arrays.stream(QuestionTypeEnum.values()).forEach(questionType -> {
            List<ExamPaperQuestionItemObject> questionItems = questions.stream()
                    .filter(q -> q.getQuestionType().equals(questionType.getCode()))
                    .map(q -> {
                        ExamPaperQuestionItemObject item = new ExamPaperQuestionItemObject();
                        item.setId(q.getId());
                        item.setItemOrder(itemOrder.getAndIncrement());
                        return item;
                    }).collect(Collectors.toList());
            if (!questionItems.isEmpty()) {
                ExamPaperTitleItemObject titleItem = new ExamPaperTitleItemObject();
                titleItem.setName(questionType.getName());
                titleItem.setQuestionItems(questionItems);
                titleItems.add(titleItem);
            }
        });
        return titleItems;
    }

    private static class ImportedGespQuestion {
        private final Question question;
        private final String content;

        ImportedGespQuestion(Question question, String content) {
            this.question = question;
            this.content = content;
        }

        Question getQuestion() {
            return question;
        }

        String getContent() {
            return content;
        }

        Integer getQuestionType() {
            return question.getQuestionType();
        }
    }

    private static class QuestionImportMetadata {
        private String importBatch;
        private String importSource;
        private Integer importQuestionOrder;

        public String getImportBatch() {
            return importBatch;
        }

        public void setImportBatch(String importBatch) {
            this.importBatch = importBatch;
        }

        public String getImportSource() {
            return importSource;
        }

        public void setImportSource(String importSource) {
            this.importSource = importSource;
        }

        public Integer getImportQuestionOrder() {
            return importQuestionOrder;
        }

        public void setImportQuestionOrder(Integer importQuestionOrder) {
            this.importQuestionOrder = importQuestionOrder;
        }
    }

    private static class GespPaperGroup {
        private final int year;
        private final int month;
        private final int level;
        private final TreeMap<Integer, Question> choiceQuestions = new TreeMap<>();
        private final TreeMap<Integer, Question> trueFalseQuestions = new TreeMap<>();

        GespPaperGroup(int year, int month, int level) {
            this.year = year;
            this.month = month;
            this.level = level;
        }

        int getYear() {
            return year;
        }

        int getMonth() {
            return month;
        }

        int getLevel() {
            return level;
        }

        TreeMap<Integer, Question> getChoiceQuestions() {
            return choiceQuestions;
        }

        TreeMap<Integer, Question> getTrueFalseQuestions() {
            return trueFalseQuestions;
        }

        boolean isComplete() {
            return choiceQuestions.size() == 15 && trueFalseQuestions.size() == 10;
        }

        String getTitle() {
            return (year % 100) + "年" + month + "月GESP" + level + "级客观题";
        }
    }
}
