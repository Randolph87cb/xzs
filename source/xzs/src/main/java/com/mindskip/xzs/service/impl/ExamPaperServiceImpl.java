package com.mindskip.xzs.service.impl;

import com.mindskip.xzs.domain.*;
import com.mindskip.xzs.domain.ExamPaper;
import com.mindskip.xzs.domain.Question;
import com.mindskip.xzs.domain.TextContent;
import com.mindskip.xzs.domain.enums.ExamPaperTypeEnum;
import com.mindskip.xzs.domain.enums.QuestionTypeEnum;
import com.mindskip.xzs.domain.exam.ExamPaperQuestionItemObject;
import com.mindskip.xzs.domain.exam.ExamPaperItemObject;
import com.mindskip.xzs.domain.exam.ExamPaperTitleItemObject;
import com.mindskip.xzs.domain.exam.QuestionSelectionUnit;
import com.mindskip.xzs.domain.other.KeyValue;
import com.mindskip.xzs.repository.ExamPaperMapper;
import com.mindskip.xzs.repository.QuestionMapper;
import com.mindskip.xzs.repository.QuestionGroupMapper;
import com.mindskip.xzs.service.ExamPaperService;
import com.mindskip.xzs.service.QuestionService;
import com.mindskip.xzs.service.SmartTrainingConfigService;
import com.mindskip.xzs.service.SubjectService;
import com.mindskip.xzs.service.TextContentService;
import com.mindskip.xzs.service.enums.ActionEnum;
import com.mindskip.xzs.utility.DateTimeUtil;
import com.mindskip.xzs.utility.JsonUtil;
import com.mindskip.xzs.utility.ExamPaperFrameUtil;
import com.mindskip.xzs.utility.QuestionSelectionUnitSelector;
import com.mindskip.xzs.utility.ModelMapperSingle;
import com.mindskip.xzs.utility.ExamUtil;
import com.mindskip.xzs.viewmodel.admin.exam.ExamPaperEditRequestVM;
import com.mindskip.xzs.viewmodel.admin.exam.ExamPaperPageRequestVM;
import com.mindskip.xzs.viewmodel.admin.exam.ExamPaperTitleItemVM;
import com.mindskip.xzs.viewmodel.admin.exam.ExamPaperItemVM;
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
import java.util.Random;
import java.util.TreeMap;
import java.util.Set;
import java.util.HashSet;
import java.util.Collections;
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
    private final QuestionGroupMapper questionGroupMapper;

    @Autowired
    public ExamPaperServiceImpl(ExamPaperMapper examPaperMapper, QuestionMapper questionMapper, TextContentService textContentService, QuestionService questionService, SubjectService subjectService, SmartTrainingConfigService smartTrainingConfigService, JdbcTemplate jdbcTemplate, QuestionGroupMapper questionGroupMapper) {
        super(examPaperMapper);
        this.examPaperMapper = examPaperMapper;
        this.questionMapper = questionMapper;
        this.textContentService = textContentService;
        this.questionService = questionService;
        this.subjectService = subjectService;
        this.smartTrainingConfigService = smartTrainingConfigService;
        this.jdbcTemplate = jdbcTemplate;
        this.questionGroupMapper = questionGroupMapper;
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
        List<ExamPaperTitleItemObject> frameTextContentList = frameTextContentFromVM(titleItemsVM, examPaperEditRequestVM.getSubjectId());
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
            examPaperFromVM(examPaperEditRequestVM, examPaper, frameTextContentList);
            examPaperMapper.insertSelective(examPaper);
        } else {
            examPaper = examPaperMapper.selectByPrimaryKey(examPaperEditRequestVM.getId());
            TextContent frameTextContent = textContentService.selectById(examPaper.getFrameTextContentId());
            frameTextContent.setContent(frameTextContentStr);
            textContentService.updateByIdFilter(frameTextContent);
            modelMapper.map(examPaperEditRequestVM, examPaper);
            examPaperFromVM(examPaperEditRequestVM, examPaper, frameTextContentList);
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

        List<QuestionSelectionUnit> selectedUnits = selectSmartTrainingUnits(subjectId, new Random());
        if (selectedUnits == null || selectedUnits.isEmpty()) {
            throw new IllegalArgumentException("当前科目暂无可用题目");
        }
        List<Question> questions = selectedUnits.stream().flatMap(unit -> unit.getQuestions().stream()).collect(Collectors.toList());

        Date now = new Date();
        List<ExamPaperTitleItemObject> titleItems = frameTextContentFromUnits(selectedUnits);
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
            Question question = importedQuestion.getQuestion();
            if (!"GESP_OBJECTIVE_MD".equals(question.getImportBatch())) {
                continue;
            }

            String importSource = question.getImportSource() == null ? "" : question.getImportSource().replace("\\", "/");
            Matcher matcher = GESP_IMPORT_SOURCE_PATTERN.matcher(importSource);
            if (!matcher.matches() || question.getImportQuestionOrder() == null) {
                continue;
            }

            int year = Integer.parseInt(matcher.group(1));
            int month = Integer.parseInt(matcher.group(2));
            int level = Integer.parseInt(matcher.group(3));
            String kind = matcher.group(4);
            int order = question.getImportQuestionOrder();
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
                "q.question_code, q.import_batch, q.import_source, q.import_question_order, q.correct, q.info_text_content_id, " +
                "q.create_user, q.status, q.create_time, q.deleted " +
                "from t_question q " +
                "where q.deleted = false and q.import_batch = 'GESP_OBJECTIVE_MD' order by q.id";
        return jdbcTemplate.query(sql, (rs, rowNum) -> {
            Question question = new Question();
            question.setId(rs.getInt("id"));
            question.setQuestionType(rs.getInt("question_type"));
            question.setSubjectId(rs.getInt("subject_id"));
            question.setScore(rs.getInt("score"));
            question.setGradeLevel(rs.getInt("grade_level"));
            question.setDifficult(rs.getInt("difficult"));
            question.setKnowledgePoint(rs.getString("knowledge_point"));
            question.setQuestionCode(rs.getString("question_code"));
            question.setImportBatch(rs.getString("import_batch"));
            question.setImportSource(rs.getString("import_source"));
            int importQuestionOrder = rs.getInt("import_question_order");
            question.setImportQuestionOrder(rs.wasNull() ? null : importQuestionOrder);
            question.setCorrect(rs.getString("correct"));
            question.setInfoTextContentId(rs.getInt("info_text_content_id"));
            question.setCreateUser(rs.getInt("create_user"));
            question.setStatus(rs.getInt("status"));
            question.setCreateTime(rs.getTimestamp("create_time"));
            question.setDeleted(rs.getBoolean("deleted"));
            return new ImportedGespQuestion(question);
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

    List<QuestionSelectionUnit> selectSmartTrainingUnits(Integer subjectId, Random random) {
        List<QuestionSelectionUnit> units = loadSelectionUnits(subjectId);
        SmartTrainingConfig config = smartTrainingConfigService.selectBySubjectId(subjectId);
        int targetQuestionCount = config == null || config.getQuestionCount() == null
                ? SMART_TRAINING_QUESTION_LIMIT : config.getQuestionCount();
        if (config == null || config.getRuleJson() == null || config.getRuleJson().length() == 0) {
            return selectExactUnits(units, targetQuestionCount, random);
        }

        List<SmartTrainingRuleVM> rules = JsonUtil.toJsonListObject(config.getRuleJson(), SmartTrainingRuleVM.class);
        if (rules == null || rules.isEmpty()) {
            return selectExactUnits(units, targetQuestionCount, random);
        }

        List<SmartTrainingRuleVM> enabledRules = rules.stream()
                .filter(rule -> !Boolean.FALSE.equals(rule.getEnabled()))
                .collect(Collectors.toList());
        if (enabledRules.isEmpty()) {
            return selectExactUnits(units, targetQuestionCount, random);
        }
        Map<SmartTrainingRuleVM, List<QuestionSelectionUnit>> unitsByRule = new HashMap<>();
        Map<SmartTrainingRuleVM, List<Integer>> optionsByRule = new HashMap<>();
        for (SmartTrainingRuleVM rule : enabledRules) {
            int minCount = smartTrainingMinCount(rule);
            int maxCount = smartTrainingMaxCount(rule);
            if (minCount > maxCount) {
                throw new IllegalArgumentException("知识点“" + rule.getKnowledgePoint() + "”下限不能大于上限");
            }
            List<QuestionSelectionUnit> ruleUnits = units.stream()
                    .filter(unit -> java.util.Objects.equals(rule.getKnowledgePoint(), unit.getKnowledgePoint()))
                    .collect(Collectors.toList());
            unitsByRule.put(rule, ruleUnits);
            Set<Integer> reachable = QuestionSelectionUnitSelector.reachableCounts(ruleUnits, Math.min(maxCount, targetQuestionCount));
            List<Integer> options = reachable.stream().filter(count -> count >= minCount && count <= maxCount)
                    .collect(Collectors.toList());
            Collections.sort(options);
            if (options.isEmpty()) {
                throw new IllegalArgumentException("知识点“" + rule.getKnowledgePoint() + "”无法在不拆题组的前提下满足题数范围");
            }
            optionsByRule.put(rule, options);
        }
        Map<SmartTrainingRuleVM, Integer> allocation = new HashMap<>();
        if (!allocateRuleCounts(enabledRules, optionsByRule, 0, targetQuestionCount, allocation,
                random, new HashMap<>())) {
            throw cannotGenerate(targetQuestionCount);
        }
        List<QuestionSelectionUnit> selected = new ArrayList<>();
        for (SmartTrainingRuleVM rule : enabledRules) {
            List<QuestionSelectionUnit> ruleSelection = QuestionSelectionUnitSelector.selectExact(
                    unitsByRule.get(rule), allocation.get(rule), random);
            if (ruleSelection == null) { throw cannotGenerate(targetQuestionCount); }
            selected.addAll(ruleSelection);
        }
        Collections.shuffle(selected, random);
        return selected;
    }

    private List<QuestionSelectionUnit> loadSelectionUnits(Integer subjectId) {
        List<QuestionSelectionUnit> units = new ArrayList<>();
        for (Question question : questionMapper.selectActiveIndependentBySubjectId(subjectId)) {
            units.add(new QuestionSelectionUnit(ExamPaperItemObject.QUESTION, question.getId(), question.getKnowledgePoint(), Arrays.asList(question)));
        }
        List<QuestionGroup> groups = questionGroupMapper.selectActiveBySubjectId(subjectId);
        if (!groups.isEmpty()) {
            Map<Integer, List<Question>> childrenByGroup = questionMapper.selectByQuestionGroupIds(
                    groups.stream().map(QuestionGroup::getId).collect(Collectors.toList())).stream()
                    .collect(Collectors.groupingBy(Question::getQuestionGroupId));
            for (QuestionGroup group : groups) {
                List<Question> children = childrenByGroup.get(group.getId());
                if (children == null || children.isEmpty()) { continue; }
                if (children.stream().anyMatch(q -> !subjectId.equals(q.getSubjectId()))) {
                    throw new IllegalStateException("题组与子题科目不一致：" + group.getId());
                }
                units.add(new QuestionSelectionUnit(ExamPaperItemObject.QUESTION_GROUP, group.getId(), group.getKnowledgePoint(), children));
            }
        }
        return units;
    }

    private List<QuestionSelectionUnit> selectExactUnits(List<QuestionSelectionUnit> units, int target, Random random) {
        List<QuestionSelectionUnit> selected = QuestionSelectionUnitSelector.selectExact(units, target, random);
        if (selected == null) { throw cannotGenerate(target); }
        return selected;
    }

    private boolean allocateRuleCounts(List<SmartTrainingRuleVM> rules,
                                       Map<SmartTrainingRuleVM, List<Integer>> options,
                                       int index, int remaining,
                                       Map<SmartTrainingRuleVM, Integer> allocation,
                                       Random random,
                                       Map<String, Double> logMassCache) {
        if (index == rules.size()) { return remaining == 0; }
        SmartTrainingRuleVM rule = rules.get(index);
        List<Integer> candidates = new ArrayList<>();
        List<Double> candidateLogMasses = new ArrayList<>();
        for (Integer count : options.get(rule)) {
            if (count > remaining) { continue; }
            double suffixLogMass = allocationLogMass(rules, options, index + 1,
                    remaining - count, logMassCache);
            if (Double.isInfinite(suffixLogMass) && suffixLogMass < 0) { continue; }
            int extraCount = Math.max(0, count - smartTrainingMinCount(rule));
            double candidateLogMass = suffixLogMass
                    + extraCount * Math.log(smartTrainingWeight(rule));
            candidates.add(count);
            candidateLogMasses.add(candidateLogMass);
        }
        if (candidates.isEmpty()) { return false; }

        int selectedIndex = candidates.size() - 1;
        if (candidates.size() > 1) {
            double maxLogMass = candidateLogMasses.stream().mapToDouble(Double::doubleValue).max().getAsDouble();
            double totalMass = candidateLogMasses.stream()
                    .mapToDouble(logMass -> Math.exp(logMass - maxLogMass))
                    .sum();
            double ticket = random.nextDouble() * totalMass;
            double cumulative = 0D;
            for (int candidateIndex = 0; candidateIndex < candidates.size(); candidateIndex++) {
                cumulative += Math.exp(candidateLogMasses.get(candidateIndex) - maxLogMass);
                if (ticket < cumulative) {
                    selectedIndex = candidateIndex;
                    break;
                }
            }
        }

        Integer selectedCount = candidates.get(selectedIndex);
        allocation.put(rule, selectedCount);
        return allocateRuleCounts(rules, options, index + 1, remaining - selectedCount,
                allocation, random, logMassCache);
    }

    private double allocationLogMass(List<SmartTrainingRuleVM> rules,
                                     Map<SmartTrainingRuleVM, List<Integer>> options,
                                     int index, int remaining,
                                     Map<String, Double> cache) {
        if (remaining < 0) { return Double.NEGATIVE_INFINITY; }
        if (index == rules.size()) { return remaining == 0 ? 0D : Double.NEGATIVE_INFINITY; }
        String cacheKey = index + ":" + remaining;
        Double cached = cache.get(cacheKey);
        if (cached != null) { return cached; }

        SmartTrainingRuleVM rule = rules.get(index);
        double totalLogMass = Double.NEGATIVE_INFINITY;
        for (Integer count : options.get(rule)) {
            if (count > remaining) { continue; }
            double suffixLogMass = allocationLogMass(rules, options, index + 1,
                    remaining - count, cache);
            if (Double.isInfinite(suffixLogMass) && suffixLogMass < 0) { continue; }
            int extraCount = Math.max(0, count - smartTrainingMinCount(rule));
            double candidateLogMass = suffixLogMass
                    + extraCount * Math.log(smartTrainingWeight(rule));
            totalLogMass = addLogMass(totalLogMass, candidateLogMass);
        }
        cache.put(cacheKey, totalLogMass);
        return totalLogMass;
    }

    private double addLogMass(double left, double right) {
        if (Double.isInfinite(left) && left < 0) { return right; }
        if (Double.isInfinite(right) && right < 0) { return left; }
        double max = Math.max(left, right);
        return max + Math.log(Math.exp(left - max) + Math.exp(right - max));
    }

    private IllegalArgumentException cannotGenerate(int target) {
        return new IllegalArgumentException("无法在不拆题组的前提下生成" + target + "题智能训练");
    }

    private int smartTrainingMinCount(SmartTrainingRuleVM rule) {
        if (rule.getMinCount() != null) {
            return rule.getMinCount();
        }
        if (rule.getQuestionCount() != null) {
            return rule.getQuestionCount();
        }
        return 0;
    }

    private int smartTrainingMaxCount(SmartTrainingRuleVM rule) {
        if (rule.getMaxCount() != null) {
            return rule.getMaxCount();
        }
        if (rule.getQuestionCount() != null) {
            return rule.getQuestionCount();
        }
        return smartTrainingMinCount(rule);
    }

    private int smartTrainingWeight(SmartTrainingRuleVM rule) {
        return rule.getWeight() == null || rule.getWeight() < 1 ? Math.max(1, smartTrainingMaxCount(rule)) : rule.getWeight();
    }

    @Override
    public ExamPaperEditRequestVM examPaperToVM(Integer id) {
        ExamPaper examPaper = examPaperMapper.selectByPrimaryKey(id);
        ExamPaperEditRequestVM vm = modelMapper.map(examPaper, ExamPaperEditRequestVM.class);
        vm.setLevel(examPaper.getGradeLevel());
        TextContent frameTextContent = textContentService.selectById(examPaper.getFrameTextContentId());
        List<ExamPaperTitleItemObject> examPaperTitleItemObjects = JsonUtil.toJsonListObject(frameTextContent.getContent(), ExamPaperTitleItemObject.class);
        List<Integer> questionIds = ExamPaperFrameUtil.expandQuestionItems(examPaperTitleItemObjects).stream()
                .map(q -> q.getId())
                .collect(Collectors.toList());
        List<Question> questions = questionMapper.selectByIds(questionIds);
        List<ExamPaperTitleItemVM> examPaperTitleItemVMS = examPaperTitleItemObjects.stream().map(t -> {
            ExamPaperTitleItemVM tTitleVM = new ExamPaperTitleItemVM();
            tTitleVM.setName(t.getName());
            List<QuestionEditRequestVM> questionItemsVM = ExamPaperFrameUtil.expandQuestionItems(t).stream()
                    .map(i -> questionItemToVM(i, questions)).collect(Collectors.toList());
            tTitleVM.setQuestionItems(questionItemsVM);
            tTitleVM.setPaperItems(paperItemsToVM(t, questions));
            return tTitleVM;
        }).collect(Collectors.toList());
        vm.setTitleItems(examPaperTitleItemVMS);
        vm.setPaperItemCount(examPaperTitleItemVMS.stream().mapToInt(t -> t.getPaperItems().size()).sum());
        vm.setScore(ExamUtil.scoreToVM(examPaper.getScore()));
        if (ExamPaperTypeEnum.TimeLimit == ExamPaperTypeEnum.fromCode(examPaper.getPaperType())) {
            List<String> limitDateTime = Arrays.asList(DateTimeUtil.dateFormat(examPaper.getLimitStartTime()), DateTimeUtil.dateFormat(examPaper.getLimitEndTime()));
            vm.setLimitDateTime(limitDateTime);
        }
        return vm;
    }

    private QuestionEditRequestVM questionItemToVM(ExamPaperQuestionItemObject item, List<Question> questions) {
        Question question = questions.stream().filter(q -> q.getId().equals(item.getId())).findFirst()
                .orElseThrow(() -> new IllegalStateException("试卷引用的题目不存在：" + item.getId()));
        QuestionEditRequestVM vm = questionService.getQuestionEditRequestVM(question);
        vm.setItemOrder(item.getItemOrder());
        vm.setGroupItemOrder(item.getGroupItemOrder() == null ? question.getGroupItemOrder() : item.getGroupItemOrder());
        return vm;
    }

    private List<ExamPaperItemVM> paperItemsToVM(ExamPaperTitleItemObject title, List<Question> questions) {
        List<ExamPaperItemObject> frameItems = title.getPaperItems();
        if (frameItems == null || frameItems.isEmpty()) {
            frameItems = new ArrayList<>();
            for (ExamPaperQuestionItemObject questionItem : ExamPaperFrameUtil.expandQuestionItems(title)) {
                ExamPaperItemObject frameItem = new ExamPaperItemObject();
                frameItem.setType(ExamPaperItemObject.QUESTION);
                frameItem.setId(questionItem.getId());
                frameItem.setItemOrder(questionItem.getItemOrder());
                frameItems.add(frameItem);
            }
        }
        List<ExamPaperItemVM> result = new ArrayList<>();
        for (ExamPaperItemObject frameItem : frameItems) {
            ExamPaperItemVM vm = new ExamPaperItemVM();
            vm.setType(frameItem.getType());
            vm.setId(frameItem.getId());
            vm.setItemOrder(frameItem.getItemOrder());
            List<ExamPaperQuestionItemObject> questionItems;
            if (ExamPaperItemObject.QUESTION_GROUP.equals(frameItem.getType())) {
                QuestionGroup group = questionGroupMapper.selectByPrimaryKey(frameItem.getId());
                if (group != null) {
                    vm.setQuestionGroupType(group.getGroupType());
                    vm.setQuestionGroupCode(group.getGroupCode());
                    TextContent content = textContentService.selectById(group.getInfoTextContentId());
                    if (content != null) {
                        vm.setTitle(JsonUtil.toJsonObject(content.getContent(), com.mindskip.xzs.domain.question.QuestionGroupObject.class).getTitleContent());
                    }
                }
                questionItems = frameItem.getQuestionItems() == null ? new ArrayList<>() : frameItem.getQuestionItems();
            } else {
                ExamPaperQuestionItemObject questionItem = new ExamPaperQuestionItemObject();
                questionItem.setId(frameItem.getId());
                questionItem.setItemOrder(frameItem.getItemOrder());
                questionItems = Arrays.asList(questionItem);
            }
            vm.setQuestionItems(questionItems.stream().map(q -> questionItemToVM(q, questions)).collect(Collectors.toList()));
            result.add(vm);
        }
        return result;
    }

    @Override
    public List<PaperInfo> indexPaper(PaperFilter paperFilter) {
        return examPaperMapper.indexPaper(paperFilter);
    }

    @Override
    public List<ExamPaper> selectByIds(List<Integer> ids) {
        return examPaperMapper.selectByIds(ids);
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

    private void examPaperFromVM(ExamPaperEditRequestVM examPaperEditRequestVM, ExamPaper examPaper, List<ExamPaperTitleItemObject> frame) {
        Integer gradeLevel = subjectService.levelBySubjectId(examPaperEditRequestVM.getSubjectId());
        List<Integer> questionIds = ExamPaperFrameUtil.expandQuestionItems(frame).stream()
                .map(ExamPaperQuestionItemObject::getId).collect(Collectors.toList());
        if (questionIds.isEmpty()) {
            throw new IllegalArgumentException("试卷至少需要一个可作答子题");
        }
        if (questionIds.stream().distinct().count() != questionIds.size()) {
            throw new IllegalArgumentException("试卷不能重复引用同一子题");
        }
        List<Question> questions = questionMapper.selectByIds(questionIds);
        if (questions.size() != questionIds.size()) {
            throw new IllegalArgumentException("试卷引用了不存在的题目");
        }
        for (Question question : questions) {
            if (!examPaperEditRequestVM.getSubjectId().equals(question.getSubjectId())) {
                throw new IllegalArgumentException("试卷与题目必须属于同一科目");
            }
        }
        Integer questionCount = questions.size();
        Integer score = questions.stream().mapToInt(Question::getScore).sum();
        examPaper.setQuestionCount(questionCount);
        examPaper.setScore(score);
        examPaper.setGradeLevel(gradeLevel);
        List<String> dateTimes = examPaperEditRequestVM.getLimitDateTime();
        if (ExamPaperTypeEnum.TimeLimit == ExamPaperTypeEnum.fromCode(examPaper.getPaperType())) {
            examPaper.setLimitStartTime(DateTimeUtil.parse(dateTimes.get(0), DateTimeUtil.STANDER_FORMAT));
            examPaper.setLimitEndTime(DateTimeUtil.parse(dateTimes.get(1), DateTimeUtil.STANDER_FORMAT));
        }
    }

    private List<ExamPaperTitleItemObject> frameTextContentFromVM(List<ExamPaperTitleItemVM> titleItems, Integer subjectId) {
        AtomicInteger index = new AtomicInteger(1);
        return titleItems.stream().map(t -> {
            ExamPaperTitleItemObject titleItem = new ExamPaperTitleItemObject();
            titleItem.setName(t.getName());
            List<ExamPaperItemObject> paperItems = new ArrayList<>();
            if (t.getPaperItems() != null && !t.getPaperItems().isEmpty()) {
                for (ExamPaperItemVM itemVM : t.getPaperItems()) {
                    paperItems.add(frameItemFromVM(itemVM, subjectId, index));
                }
            } else if (t.getQuestionItems() != null) {
                for (QuestionEditRequestVM questionVM : t.getQuestionItems()) {
                    ExamPaperItemVM itemVM = new ExamPaperItemVM();
                    itemVM.setType(ExamPaperItemObject.QUESTION);
                    itemVM.setId(questionVM.getId());
                    paperItems.add(frameItemFromVM(itemVM, subjectId, index));
                }
            }
            if (paperItems.isEmpty()) {
                throw new IllegalArgumentException("试卷标题“" + t.getName() + "”至少需要一个题目或题组");
            }
            titleItem.setPaperItems(paperItems);
            titleItem.setQuestionItems(null);
            return titleItem;
        }).collect(Collectors.toList());
    }

    private ExamPaperItemObject frameItemFromVM(ExamPaperItemVM itemVM, Integer subjectId, AtomicInteger itemOrder) {
        if (itemVM.getId() == null) {
            throw new IllegalArgumentException("试卷条目ID不能为空");
        }
        ExamPaperItemObject item = new ExamPaperItemObject();
        item.setId(itemVM.getId());
        if (ExamPaperItemObject.QUESTION_GROUP.equals(itemVM.getType())) {
            QuestionGroup group = questionGroupMapper.selectByPrimaryKey(itemVM.getId());
            if (group == null || Boolean.TRUE.equals(group.getDeleted()) || !Integer.valueOf(1).equals(group.getStatus())) {
                throw new IllegalArgumentException("题组不存在或未启用：" + itemVM.getId());
            }
            if (!subjectId.equals(group.getSubjectId())) {
                throw new IllegalArgumentException("试卷与题组必须属于同一科目");
            }
            List<Question> children = questionMapper.selectByQuestionGroupId(group.getId()).stream()
                    .filter(q -> !Boolean.TRUE.equals(q.getDeleted()) && Integer.valueOf(1).equals(q.getStatus()))
                    .collect(Collectors.toList());
            if (children.isEmpty()) {
                throw new IllegalArgumentException("有效题组至少需要一个子题：" + itemVM.getId());
            }
            List<ExamPaperQuestionItemObject> snapshots = new ArrayList<>();
            for (Question child : children) {
                if (!subjectId.equals(child.getSubjectId())) {
                    throw new IllegalArgumentException("题组与子题必须属于同一科目");
                }
                ExamPaperQuestionItemObject snapshot = new ExamPaperQuestionItemObject();
                snapshot.setId(child.getId());
                snapshot.setGroupItemOrder(child.getGroupItemOrder());
                snapshot.setItemOrder(itemOrder.getAndIncrement());
                snapshots.add(snapshot);
            }
            item.setType(ExamPaperItemObject.QUESTION_GROUP);
            item.setItemOrder(snapshots.get(0).getItemOrder());
            item.setQuestionItems(snapshots);
        } else {
            Question question = questionMapper.selectByPrimaryKey(itemVM.getId());
            if (question == null || Boolean.TRUE.equals(question.getDeleted()) || !Integer.valueOf(1).equals(question.getStatus())) {
                throw new IllegalArgumentException("题目不存在或未启用：" + itemVM.getId());
            }
            if (question.getQuestionGroupId() != null) {
                throw new IllegalArgumentException("题组子题不能作为独立题加入试卷：" + itemVM.getId());
            }
            if (!subjectId.equals(question.getSubjectId())) {
                throw new IllegalArgumentException("试卷与题目必须属于同一科目");
            }
            item.setType(ExamPaperItemObject.QUESTION);
            item.setItemOrder(itemOrder.getAndIncrement());
        }
        return item;
    }

    private List<ExamPaperTitleItemObject> frameTextContentFromQuestions(List<Question> questions) {
        List<ExamPaperTitleItemObject> titleItems = new ArrayList<>();
        AtomicInteger itemOrder = new AtomicInteger(1);
        Arrays.stream(QuestionTypeEnum.values()).forEach(questionType -> {
            List<ExamPaperItemObject> paperItems = questions.stream()
                    .filter(q -> q.getQuestionType().equals(questionType.getCode()))
                    .map(q -> {
                        ExamPaperItemObject item = new ExamPaperItemObject();
                        item.setType(ExamPaperItemObject.QUESTION);
                        item.setId(q.getId());
                        item.setItemOrder(itemOrder.getAndIncrement());
                        return item;
                    }).collect(Collectors.toList());
            if (!paperItems.isEmpty()) {
                ExamPaperTitleItemObject titleItem = new ExamPaperTitleItemObject();
                titleItem.setName(questionType.getName());
                titleItem.setPaperItems(paperItems);
                titleItems.add(titleItem);
            }
        });
        return titleItems;
    }

    private List<ExamPaperTitleItemObject> frameTextContentFromUnits(List<QuestionSelectionUnit> units) {
        ExamPaperTitleItemObject title = new ExamPaperTitleItemObject();
        title.setName("智能训练");
        List<ExamPaperItemObject> paperItems = new ArrayList<>();
        AtomicInteger itemOrder = new AtomicInteger(1);
        for (QuestionSelectionUnit unit : units) {
            ExamPaperItemObject item = new ExamPaperItemObject();
            item.setType(unit.getType());
            item.setId(unit.getId());
            if (ExamPaperItemObject.QUESTION_GROUP.equals(unit.getType())) {
                List<ExamPaperQuestionItemObject> snapshots = new ArrayList<>();
                for (Question question : unit.getQuestions()) {
                    ExamPaperQuestionItemObject snapshot = new ExamPaperQuestionItemObject();
                    snapshot.setId(question.getId());
                    snapshot.setGroupItemOrder(question.getGroupItemOrder());
                    snapshot.setItemOrder(itemOrder.getAndIncrement());
                    snapshots.add(snapshot);
                }
                item.setItemOrder(snapshots.get(0).getItemOrder());
                item.setQuestionItems(snapshots);
            } else {
                item.setItemOrder(itemOrder.getAndIncrement());
            }
            paperItems.add(item);
        }
        title.setPaperItems(paperItems);
        return Arrays.asList(title);
    }

    private static class ImportedGespQuestion {
        private final Question question;

        ImportedGespQuestion(Question question) {
            this.question = question;
        }

        Question getQuestion() {
            return question;
        }

        Integer getQuestionType() {
            return question.getQuestionType();
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
