package com.mindskip.xzs.utility;

import com.mindskip.xzs.domain.exam.QuestionSelectionUnit;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Random;
import java.util.Set;

public final class QuestionSelectionUnitSelector {
    private QuestionSelectionUnitSelector() { }

    public static Set<Integer> reachableCounts(List<QuestionSelectionUnit> units, int maxCount) {
        Set<Integer> reachable = new HashSet<>();
        reachable.add(0);
        for (QuestionSelectionUnit unit : units) {
            List<Integer> snapshot = new ArrayList<>(reachable);
            for (Integer count : snapshot) {
                int next = count + unit.getQuestionCount();
                if (next <= maxCount) { reachable.add(next); }
            }
        }
        return reachable;
    }

    public static List<QuestionSelectionUnit> selectExact(List<QuestionSelectionUnit> source, int target, Random random) {
        List<QuestionSelectionUnit> units = new ArrayList<>(source);
        Collections.shuffle(units, random);
        Map<Integer, List<QuestionSelectionUnit>> selected = new HashMap<>();
        selected.put(0, new ArrayList<>());
        for (QuestionSelectionUnit unit : units) {
            List<Integer> counts = new ArrayList<>(selected.keySet());
            Collections.sort(counts, Collections.reverseOrder());
            for (Integer count : counts) {
                int next = count + unit.getQuestionCount();
                if (next > target || selected.containsKey(next)) { continue; }
                List<QuestionSelectionUnit> nextSelection = new ArrayList<>(selected.get(count));
                nextSelection.add(unit);
                selected.put(next, nextSelection);
            }
        }
        return selected.get(target);
    }
}
